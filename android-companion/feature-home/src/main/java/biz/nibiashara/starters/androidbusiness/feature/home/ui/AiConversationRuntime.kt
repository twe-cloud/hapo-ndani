/*
 * Copyright (C) 2022 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package biz.nibiashara.ndani.companion.feature.home.ui

import android.content.Context
import android.net.Uri
import android.os.Build
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.AssetPackStateUpdateListener
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface AiConversationRuntime {
    val status: StateFlow<AiRuntimeStatus>
    val provisioningStatus: StateFlow<AiProvisioningStatus>

    suspend fun importModel(uri: Uri): AiRuntimeStatus

    suspend fun provisionAutomatically(): AiProvisioningStatus

    suspend fun generate(prompt: String): AiRuntimeReply
}

@Singleton
class LiteRtLmConversationRuntime @Inject constructor(
    @param:ApplicationContext private val context: Context
) : AiConversationRuntime {

    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
    private val runtimeScope = CoroutineScope(SupervisorJob() + ioDispatcher)
    private val engineMutex = Mutex()
    private val provisionMutex = Mutex()
    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var loadedModelPath: String? = null
    private val _status = MutableStateFlow(scanStatus())
    private val _provisioningStatus = MutableStateFlow(scanProvisioningStatus())
    private val assetPackManager: AssetPackManager by lazy {
        AssetPackManagerFactory.getInstance(context)
    }
    private val assetPackListener = AssetPackStateUpdateListener { assetPackState ->
        if (assetPackState.name() !in MODEL_ASSET_PACK_NAMES) return@AssetPackStateUpdateListener

        when (assetPackState.status()) {
            AssetPackStatus.PENDING,
            AssetPackStatus.DOWNLOADING,
            AssetPackStatus.TRANSFERRING -> {
                _provisioningStatus.value = AiProvisioningStatus.Installing(
                    message = "Setting up the personal AI model automatically.",
                    bytesDownloaded = assetPackState.bytesDownloaded(),
                    totalBytesToDownload = assetPackState.totalBytesToDownload()
                )
            }
            AssetPackStatus.COMPLETED -> {
                runtimeScope.launch {
                    provisionAutomatically()
                }
            }
            AssetPackStatus.WAITING_FOR_WIFI -> {
                _provisioningStatus.value = AiProvisioningStatus.WaitingForPlayDelivery(
                    "Personal AI setup is waiting for Wi-Fi."
                )
            }
            AssetPackStatus.REQUIRES_USER_CONFIRMATION -> {
                _provisioningStatus.value = AiProvisioningStatus.NeedsUserAction(
                    "Google Play needs confirmation before downloading the personal AI model."
                )
            }
            AssetPackStatus.FAILED,
            AssetPackStatus.CANCELED,
            AssetPackStatus.NOT_INSTALLED,
            AssetPackStatus.UNKNOWN -> {
                _provisioningStatus.value = AiProvisioningStatus.NeedsUserAction(
                    "Automatic model delivery is not ready on this install. Choose a model file to test locally."
                )
            }
        }
    }

    override val status: StateFlow<AiRuntimeStatus> = _status.asStateFlow()
    override val provisioningStatus: StateFlow<AiProvisioningStatus> = _provisioningStatus.asStateFlow()

    init {
        runCatching { assetPackManager.registerListener(assetPackListener) }
    }

    override suspend fun importModel(uri: Uri): AiRuntimeStatus = withContext(ioDispatcher) {
        engineMutex.withLock { closeEngine() }
        val modelDirectory = File(context.noBackupFilesDir, "models").apply { mkdirs() }
        val stagingFile = File(modelDirectory, "${DEFAULT_MODEL_FILE_NAME}.import.tmp")
        val modelFile = File(modelDirectory, DEFAULT_MODEL_FILE_NAME)

        try {
            val input = context.contentResolver.openInputStream(uri)
                ?: run {
                    val failed = AiRuntimeStatus.LoadFailed(
                        modelPath = modelDirectory.absolutePath,
                        detail = "Could not open selected model file."
                    )
                    _status.value = failed
                    return@withContext failed
                }
            input.use { stream ->
                stagingFile.outputStream().use { output ->
                    stream.copyTo(output)
                }
            }

            if (stagingFile.length() < 64L) {
                stagingFile.delete()
                val failed = AiRuntimeStatus.LoadFailed(
                    modelPath = modelDirectory.absolutePath,
                    detail = "Imported file is too small to be a valid model."
                )
                _status.value = failed
                return@withContext failed
            }

            if (!stagingFile.hasLiteRtLmHeader()) {
                stagingFile.delete()
                val failed = AiRuntimeStatus.LoadFailed(
                    modelPath = modelDirectory.absolutePath,
                    detail = "Imported file is not a supported LiteRT-LM model."
                )
                _status.value = failed
                return@withContext failed
            }

            if (modelFile.exists()) modelFile.delete()
            if (!stagingFile.renameTo(modelFile)) {
                stagingFile.inputStream().use { src ->
                    modelFile.outputStream().use { dst -> src.copyTo(dst) }
                }
                stagingFile.delete()
            }

            val nextStatus = AiRuntimeStatus.Found(modelFile.absolutePath)
            _status.value = nextStatus
            _provisioningStatus.value = AiProvisioningStatus.Ready("Model imported for this device.")
            nextStatus
        } catch (e: Exception) {
            stagingFile.delete()
            val failed = AiRuntimeStatus.LoadFailed(
                modelPath = modelDirectory.absolutePath,
                detail = "Model import failed: ${e.message ?: e::class.java.simpleName}"
            )
            _status.value = failed
            failed
        }
    }

    override suspend fun provisionAutomatically(): AiProvisioningStatus = withContext(ioDispatcher) {
        provisionMutex.withLock {
            findModelFile()?.let { existing ->
                val ready = AiProvisioningStatus.Ready("Personal AI is installed on this device.")
                _status.value = AiRuntimeStatus.Found(existing.absolutePath)
                _provisioningStatus.value = ready
                return@withLock ready
            }

            _provisioningStatus.value = AiProvisioningStatus.Installing(
                message = "Looking for the included personal AI model.",
                bytesDownloaded = 0L,
                totalBytesToDownload = 0L
            )

            copyModelFromBundledAssets()?.let { copied ->
                val ready = AiProvisioningStatus.Ready("Personal AI model installed from the app package.")
                _status.value = AiRuntimeStatus.Found(copied.absolutePath)
                _provisioningStatus.value = ready
                return@withLock ready
            }

            copyModelFromPlayAssetPacks()?.let { copied ->
                val ready = AiProvisioningStatus.Ready("Personal AI model installed from Google Play delivery.")
                _status.value = AiRuntimeStatus.Found(copied.absolutePath)
                _provisioningStatus.value = ready
                return@withLock ready
            }

            requestPlayAssetDelivery()
        }
    }

    override suspend fun generate(prompt: String): AiRuntimeReply = withContext(ioDispatcher) {
        val modelFile = findModelFile()
        if (modelFile == null) {
            val nextStatus = scanStatus()
            _status.value = nextStatus
            return@withContext when (nextStatus) {
                is AiRuntimeStatus.MissingModel -> AiRuntimeReply.MissingModel(nextStatus)
                else -> {
                    val failed = AiRuntimeStatus.LoadFailed(
                        modelPath = "",
                        detail = "No model file found on this device."
                    )
                    _status.value = failed
                    AiRuntimeReply.Failed(failed, IllegalStateException("No model file found"))
                }
            }
        }

        emulatorLoadBlock(modelFile)?.let { blockedStatus ->
            _status.value = blockedStatus
            return@withContext AiRuntimeReply.Failed(blockedStatus, IllegalStateException(blockedStatus.detail))
        }

        engineMutex.withLock {
            try {
                val chat = conversationFor(modelFile)
                _status.value = AiRuntimeStatus.Ready(modelFile.absolutePath)
                val rawResponse = chat.sendMessage(prompt)
                    ?: throw IllegalStateException("LiteRT-LM returned null for the prompt.")
                val response = rawResponse.asPlainText()
                if (response.isBlank()) {
                    AiRuntimeReply.Failed(
                        status = AiRuntimeStatus.LoadFailed(
                            modelPath = modelFile.absolutePath,
                            detail = "LiteRT-LM returned an empty response."
                        ),
                        throwable = IllegalStateException("LiteRT-LM returned an empty response")
                    )
                } else {
                    AiRuntimeReply.Generated(response)
                }
            } catch (throwable: Throwable) {
                closeEngine()
                val failed = AiRuntimeStatus.LoadFailed(
                    modelPath = modelFile.absolutePath,
                    detail = throwable.message ?: throwable::class.java.simpleName
                )
                _status.value = failed
                AiRuntimeReply.Failed(failed, throwable)
            }
        }
    }

    private fun conversationFor(modelFile: File): Conversation {
        if (loadedModelPath == modelFile.absolutePath) {
            conversation?.let { return it }
        }

        closeEngine()

        val nextEngine: Engine
        try {
            nextEngine = Engine(
                EngineConfig(
                    modelPath = modelFile.absolutePath,
                    backend = Backend.CPU(),
                    cacheDir = File(context.noBackupFilesDir, "litertlm-cache").apply { mkdirs() }.absolutePath
                )
            )
            nextEngine.initialize()
        } catch (e: UnsatisfiedLinkError) {
            throw IllegalStateException("LiteRT-LM native library failed to load on this device.", e)
        } catch (e: ExceptionInInitializerError) {
            throw IllegalStateException("LiteRT-LM native initialization failed on this device.", e)
        }

        val nextConversation = nextEngine.createConversation(
            ConversationConfig(
                systemInstruction = Contents.of(HAPO_NDANI_SYSTEM_INSTRUCTION),
                samplerConfig = SamplerConfig(
                    topK = 32,
                    topP = 0.9,
                    temperature = 0.7
                )
            )
        ) ?: run {
            nextEngine.close()
            throw IllegalStateException("LiteRT-LM engine created but conversation initialization returned null.")
        }

        engine = nextEngine
        conversation = nextConversation
        loadedModelPath = modelFile.absolutePath
        return nextConversation
    }

    private fun closeEngine() {
        runCatching { conversation?.close() }
        runCatching { engine?.close() }
        conversation = null
        engine = null
        loadedModelPath = null
    }

    private fun scanStatus(): AiRuntimeStatus {
        val modelFile = findModelFile()
        return if (modelFile == null) {
            AiRuntimeStatus.MissingModel(
                modelNames = MODEL_FILE_NAMES,
                installLocations = modelDirectories().map { it.absolutePath }
            )
        } else {
            AiRuntimeStatus.Found(modelFile.absolutePath)
        }
    }

    private fun scanProvisioningStatus(): AiProvisioningStatus =
        if (findModelFile() == null) {
            AiProvisioningStatus.NeedsUserAction(
                "Personal AI setup has not finished on this device."
            )
        } else {
            AiProvisioningStatus.Ready("Personal AI is installed on this device.")
        }

    private fun copyModelFromBundledAssets(): File? {
        for (modelName in MODEL_FILE_NAMES) {
            val assetPath = "models/$modelName"
            val copied = runCatching {
                context.assets.open(assetPath).use { input ->
                    copyModelToPrivateStorage(modelName, input)
                }
            }.getOrNull()
            if (copied != null) return copied
        }
        return null
    }

    private fun copyModelFromPlayAssetPacks(): File? {
        copyWholeModelFromPlayAssetPack()?.let { return it }
        return copyChunkedModelFromPlayAssetPacks()
    }

    private fun copyWholeModelFromPlayAssetPack(): File? {
        for (packName in MODEL_ASSET_PACK_NAMES) {
            val assetsPath = runCatching {
                assetPackManager.getPackLocation(packName)?.assetsPath()
            }.getOrNull() ?: continue

            val assetRoot = File(assetsPath, "models")
            val modelFile = MODEL_FILE_NAMES
                .asSequence()
                .map { File(assetRoot, it) }
                .firstOrNull { it.isFile && it.canRead() && it.length() > 0L }
            if (modelFile != null && modelFile.hasLiteRtLmHeader()) {
                return modelFile.inputStream().use { input ->
                    copyModelToPrivateStorage(modelFile.name, input)
                }
            }
        }
        return null
    }

    private fun copyChunkedModelFromPlayAssetPacks(): File? {
        val chunkFiles = MODEL_ASSET_PACK_NAMES.mapIndexed { index, packName ->
            val location = runCatching {
                assetPackManager.getPackLocation(packName)
            }.getOrNull() ?: return null
            val assetsPath = location.assetsPath() ?: return null
            File(assetsPath, "model_chunks/$DEFAULT_MODEL_FILE_NAME.part${index.toString().padStart(2, '0')}")
                .takeIf { it.isFile && it.canRead() && it.length() > 0L }
                ?: return null
        }

        closeEngine()
        val modelDirectory = File(context.noBackupFilesDir, "models").apply { mkdirs() }
        val modelFile = File(modelDirectory, DEFAULT_MODEL_FILE_NAME)
        val stagingFile = File(modelDirectory, "$DEFAULT_MODEL_FILE_NAME.play.tmp")
        try {
            stagingFile.outputStream().use { output ->
                chunkFiles.forEach { chunk ->
                    chunk.inputStream().use { input ->
                        input.copyTo(output)
                    }
                }
            }
        } catch (_: Exception) {
            stagingFile.delete()
            return null
        }
        if (!stagingFile.hasLiteRtLmHeader()) {
            stagingFile.delete()
            return null
        }
        if (modelFile.exists()) modelFile.delete()
        if (!stagingFile.renameTo(modelFile)) {
            runCatching {
                stagingFile.inputStream().use { src ->
                    modelFile.outputStream().use { dst -> src.copyTo(dst) }
                }
                stagingFile.delete()
            }.onFailure {
                stagingFile.delete()
                return null
            }
        }
        return modelFile
    }

    private fun copyModelToPrivateStorage(modelName: String, input: InputStream): File {
        closeEngine()
        val modelDirectory = File(context.noBackupFilesDir, "models").apply { mkdirs() }
        val modelFile = File(modelDirectory, DEFAULT_MODEL_FILE_NAME)
        val stagingFile = File(modelDirectory, "$modelName.tmp")
        stagingFile.outputStream().use { output ->
            input.copyTo(output)
        }
        if (stagingFile.length() <= 0L) {
            stagingFile.delete()
            error("Selected model file was empty.")
        }
        if (!stagingFile.hasLiteRtLmHeader()) {
            stagingFile.delete()
            error("Selected model file is not a supported LiteRT-LM model.")
        }
        if (modelFile.exists()) modelFile.delete()
        if (!stagingFile.renameTo(modelFile)) {
            stagingFile.inputStream().use { src ->
                modelFile.outputStream().use { dst -> src.copyTo(dst) }
            }
            stagingFile.delete()
        }
        return modelFile
    }

    private fun requestPlayAssetDelivery(): AiProvisioningStatus {
        if (!isInstalledFromGooglePlay()) {
            return AiProvisioningStatus.NeedsUserAction(
                "Automatic model delivery only runs from a Google Play install. Choose a model file to test locally."
            ).also { status ->
                _provisioningStatus.value = status
            }
        }

        return runCatching {
            val missingPacks = MODEL_ASSET_PACK_NAMES.filter { packName ->
                assetPackManager.getPackLocation(packName) == null
            }
            if (missingPacks.isEmpty()) {
                AiProvisioningStatus.NeedsUserAction(
                    "The model packs were delivered, but they did not contain a supported Gemma 3n E2B `.litertlm` file."
                )
            } else {
                assetPackManager.fetch(missingPacks)
                AiProvisioningStatus.WaitingForPlayDelivery(
                    "Personal AI setup is downloading automatically from Google Play."
                )
            }
        }.getOrElse { throwable ->
            AiProvisioningStatus.NeedsUserAction(
                "Automatic Play delivery is unavailable in this build. Choose a model file to test locally. ${throwable.message.orEmpty()}".trim()
            )
        }.also { status ->
            _provisioningStatus.value = status
        }
    }

    @Suppress("DEPRECATION")
    private fun isInstalledFromGooglePlay(): Boolean {
        val installerPackageName = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.packageManager
                    .getInstallSourceInfo(context.packageName)
                    .installingPackageName
            } else {
                context.packageManager.getInstallerPackageName(context.packageName)
            }
        }.getOrNull()
        return installerPackageName == "com.android.vending"
    }

    private fun findModelFile(): File? =
        modelDirectories()
            .asSequence()
            .flatMap { directory -> MODEL_FILE_NAMES.asSequence().map { File(directory, it) } }
            .firstOrNull { it.isFile && it.canRead() && it.length() > 0L }

    private fun emulatorLoadBlock(modelFile: File): AiRuntimeStatus.LoadFailed? {
        if (!isProbablyEmulator()) return null
        return AiRuntimeStatus.LoadFailed(
            modelPath = modelFile.absolutePath,
            detail = "Gemma 3n E2B LiteRT-LM is present, but this Android emulator cannot safely initialize the native runtime. Test this model on an 8 GB+ physical Android phone."
        )
    }

    private fun isProbablyEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        val product = Build.PRODUCT.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        return fingerprint.startsWith("generic") ||
            fingerprint.contains("emulator") ||
            model.contains("sdk_gphone") ||
            model.contains("emulator") ||
            product.contains("sdk_gphone") ||
            product.contains("emulator") ||
            hardware.contains("ranchu") ||
            hardware.contains("goldfish") ||
            manufacturer == "genymotion"
    }

    private fun modelDirectories(): List<File> = listOfNotNull(
        File(context.noBackupFilesDir, "models"),
        File(context.filesDir, "models")
        // External files directory excluded — readable by other apps with storage permissions
    ).onEach { it.mkdirs() }

    companion object {
        const val DEFAULT_MODEL_FILE_NAME = "gemma-3n-E2B-it-int4.litertlm"
        val MODEL_FILE_NAMES = listOf(
            DEFAULT_MODEL_FILE_NAME,
            "gemma-3n-E2B-it.litertlm",
            "gemma-3n-E2B-it-litertlm.litertlm",
            "gemma-3n-E2B-it-litert-lm.litertlm",
            "gemma-3n-E4B-it-int4.litertlm",
            "gemma-3n-E4B-it.litertlm",
            "gemma-3n-E4B-it-litertlm.litertlm",
            "gemma-3n-E4B-it-litert-lm.litertlm"
        )
        val MODEL_ASSET_PACK_NAMES = listOf(
            "hapondani_model_pack_0",
            "hapondani_model_pack_1",
            "hapondani_model_pack_2"
        )
    }
}

private fun File.hasLiteRtLmHeader(): Boolean =
    runCatching {
        inputStream().use { input ->
            val header = ByteArray(LITERTLM_MAGIC.size)
            input.read(header) == LITERTLM_MAGIC.size && header.contentEquals(LITERTLM_MAGIC)
        }
    }.getOrDefault(false)

private val LITERTLM_MAGIC = "LITERTLM".encodeToByteArray()

private fun com.google.ai.edge.litertlm.Message.asPlainText(): String =
    contents.contents
        .filterIsInstance<Content.Text>()
        .joinToString(separator = "") { it.text }
        .trim()

const val HAPO_NDANI_SYSTEM_INSTRUCTION =
    "You are Hapo Ndani, a private local companion for planning, writing, journaling, and memory. " +
        "Be warm, concise, practical, and human. Do not claim to be a device troubleshooting assistant. " +
        "Do not mention cloud services. If the user is vague, ask one useful question or offer clear next steps."

sealed interface AiRuntimeStatus {
    data class MissingModel(
        val modelNames: List<String>,
        val installLocations: List<String>
    ) : AiRuntimeStatus

    data class Found(val modelPath: String) : AiRuntimeStatus

    data class Ready(val modelPath: String) : AiRuntimeStatus

    data class LoadFailed(
        val modelPath: String,
        val detail: String
    ) : AiRuntimeStatus
}

sealed interface AiRuntimeReply {
    data class Generated(val text: String) : AiRuntimeReply
    data class MissingModel(val status: AiRuntimeStatus.MissingModel) : AiRuntimeReply
    data class Failed(val status: AiRuntimeStatus.LoadFailed, val throwable: Throwable) : AiRuntimeReply
}

sealed interface AiProvisioningStatus {
    data class Ready(val message: String) : AiProvisioningStatus

    data class Installing(
        val message: String,
        val bytesDownloaded: Long,
        val totalBytesToDownload: Long
    ) : AiProvisioningStatus

    data class WaitingForPlayDelivery(val message: String) : AiProvisioningStatus

    data class NeedsUserAction(val message: String) : AiProvisioningStatus
}
