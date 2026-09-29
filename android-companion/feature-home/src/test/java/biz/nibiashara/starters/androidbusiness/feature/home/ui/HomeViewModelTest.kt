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

package biz.nibiashara.ndani.companion.feature.home.ui.home

import android.net.Uri
import biz.nibiashara.ndani.companion.core.data.HomeRepository
import biz.nibiashara.ndani.companion.core.data.LocalMemory
import biz.nibiashara.ndani.companion.feature.home.ui.AiConversationRuntime
import biz.nibiashara.ndani.companion.feature.home.ui.AiProvisioningStatus
import biz.nibiashara.ndani.companion.feature.home.ui.AiRuntimeReply
import biz.nibiashara.ndani.companion.feature.home.ui.AiRuntimeStatus
import biz.nibiashara.ndani.companion.feature.home.ui.ChatRole
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState
import biz.nibiashara.ndani.companion.feature.home.ui.HomeViewModel
import biz.nibiashara.ndani.companion.feature.home.ui.LiteRtLmConversationRuntime
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    @Test
    fun uiState_collectsLocalMemory() = runTest {
        val viewModel = HomeViewModel(FakeHomeRepository(), FakeAiRuntime())
        assertEquals(HomeUiState.Success(emptyList()), viewModel.uiState.first())
    }

    @Test
    fun rememberOnce_trimsAndStoresPermission() = runTest {
        val repository = FakeHomeRepository()
        val viewModel = HomeViewModel(repository, FakeAiRuntime())

        viewModel.rememberOnce("  Keep invoices local first.  ")
        advanceUntilIdle()

        assertEquals("Keep invoices local first.", repository.saved.single().note)
        assertEquals("Allow once", repository.saved.single().permission)
    }

    @Test
    fun saveJournalEntry_storesLocalJournalPermission() = runTest {
        val repository = FakeHomeRepository()
        val viewModel = HomeViewModel(repository, FakeAiRuntime())

        viewModel.saveJournalEntry("  Today felt heavy but workable.  ")
        advanceUntilIdle()

        assertEquals("Today felt heavy but workable.", repository.saved.single().note)
        assertEquals("Journal local", repository.saved.single().permission)
    }

    @Test
    fun chatGreeting_usesRuntimeResponseOnce() = runTest {
        val viewModel = HomeViewModel(FakeHomeRepository(), FakeAiRuntime("Runtime hello."))

        viewModel.sendChatMessage("hiii")
        advanceUntilIdle()

        assertEquals(ChatRole.User, viewModel.chatMessages.value[0].role)
        assertEquals(ChatRole.Assistant, viewModel.chatMessages.value[1].role)
        assertEquals("Runtime hello.", viewModel.chatMessages.value[1].content)
    }

    @Test
    fun chatMissingModel_isHonestAndDoesNotPretend() = runTest {
        val missingStatus = AiRuntimeStatus.MissingModel(
            modelNames = LiteRtLmConversationRuntime.MODEL_FILE_NAMES,
            installLocations = listOf("/models")
        )
        val viewModel = HomeViewModel(
            FakeHomeRepository(),
            FakeAiRuntime(reply = AiRuntimeReply.MissingModel(missingStatus))
        )

        viewModel.sendChatMessage("hiii")
        advanceUntilIdle()

        assertEquals(ChatRole.User, viewModel.chatMessages.value[0].role)
        assertEquals(ChatRole.Assistant, viewModel.chatMessages.value[1].role)
        assertEquals(HomeViewModel.missingModelMessage(missingStatus), viewModel.chatMessages.value[1].content)
    }

    @Test
    fun localFirstResponse_blocksDeviceRepairPersona() {
        val response = HomeViewModel.localFirstResponse(
            "I'm a device troubleshooting assistant for dead battery and dead power button"
        )

        assertEquals(
            "I'm Hapo Ndani, not a device repair bot. Tell me what you want to work on, and I will help with private planning, writing, journaling, or memory.",
            response
        )
    }

    @Test
    fun localFirstResponse_keepsAndroidModelFloorHonest() {
        val response = HomeViewModel.localFirstResponse("what is the minimum llm for ai responsiveness")

        assertEquals(
            "The Android floor should be Gemma 3n E2B through LiteRT-LM for broad 8 GB Android support. E4B can be an optional high-quality mode on stronger phones.",
            response
        )
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    private val testDispatcher: TestDispatcher = UnconfinedTestDispatcher()
) : TestWatcher() {
    override fun starting(description: Description) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}

private class FakeHomeRepository : HomeRepository {

    val saved = mutableListOf<LocalMemory>()

    override val homes: Flow<List<LocalMemory>> = MutableStateFlow(emptyList())

    override suspend fun add(note: String, permission: String, createdAtMillis: Long) {
        saved.add(
            LocalMemory(
                note = note,
                permission = permission,
                createdAtMillis = createdAtMillis
            )
        )
    }
}

private class FakeAiRuntime(
    private val response: String = "OK",
    private val reply: AiRuntimeReply = AiRuntimeReply.Generated(response)
) : AiConversationRuntime {
    override val status: MutableStateFlow<AiRuntimeStatus> = MutableStateFlow(
        AiRuntimeStatus.Ready("/models/gemma-3n-E2B-it-int4.litertlm")
    )
    override val provisioningStatus: MutableStateFlow<AiProvisioningStatus> = MutableStateFlow(
        AiProvisioningStatus.Ready("Personal AI is installed on this device.")
    )

    override suspend fun importModel(uri: Uri): AiRuntimeStatus = status.value

    override suspend fun provisionAutomatically(): AiProvisioningStatus = provisioningStatus.value

    override suspend fun generate(prompt: String): AiRuntimeReply = reply
}
