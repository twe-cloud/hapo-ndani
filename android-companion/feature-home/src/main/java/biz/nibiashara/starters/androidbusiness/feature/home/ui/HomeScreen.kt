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

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import biz.nibiashara.ndani.companion.core.data.LocalMemory
import biz.nibiashara.ndani.companion.core.designsystem.MyApplicationTheme
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Error
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Loading
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Success

@Composable
fun HomeScreen(
    onItemClick: (NavKey) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: HomeViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val chatMessages by viewModel.chatMessages.collectAsStateWithLifecycle()
    val runtimeStatus by viewModel.runtimeStatus.collectAsStateWithLifecycle()
    val provisioningStatus by viewModel.provisioningStatus.collectAsStateWithLifecycle()
    HomeScreen(
        state = state,
        chatMessages = chatMessages,
        runtimeStatus = runtimeStatus,
        provisioningStatus = provisioningStatus,
        onModelImport = viewModel::importModel,
        onSetUpPersonalAi = viewModel::setUpPersonalAi,
        onRememberOnce = viewModel::rememberOnce,
        onJournalSave = viewModel::saveJournalEntry,
        onSendChat = viewModel::sendChatMessage,
        modifier = modifier
    )
}

@Composable
internal fun HomeScreen(
    state: HomeUiState,
    chatMessages: List<ChatMessage>,
    runtimeStatus: AiRuntimeStatus,
    provisioningStatus: AiProvisioningStatus,
    onModelImport: (Uri) -> Unit,
    onSetUpPersonalAi: () -> Unit,
    onRememberOnce: (note: String) -> Unit,
    onJournalSave: (entry: String) -> Unit,
    onSendChat: (message: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var selectedTab by rememberSaveable { mutableStateOf(AndroidTab.Home) }

    Box(
        modifier = modifier
            .fillMaxSize()
            .safeDrawingPadding()
    ) {
        when (selectedTab) {
            AndroidTab.Home -> HomeTab(
                state = state,
                runtimeStatus = runtimeStatus,
                provisioningStatus = provisioningStatus,
                onModelImport = onModelImport,
                onSetUpPersonalAi = onSetUpPersonalAi,
                onRememberOnce = onRememberOnce,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 92.dp)
            )
            AndroidTab.Chat -> ChatTab(
                messages = chatMessages,
                runtimeStatus = runtimeStatus,
                onSendChat = onSendChat,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 92.dp)
            )
            AndroidTab.Journal -> JournalTab(
                onJournalSave = onJournalSave,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 92.dp)
            )
        }

        NavigationBar(
            modifier = Modifier.align(Alignment.BottomCenter),
            containerColor = MaterialTheme.colorScheme.surface
        ) {
            AndroidTab.entries.forEach { tab ->
                NavigationBarItem(
                    selected = selectedTab == tab,
                    onClick = { selectedTab = tab },
                    label = { Text(tab.title) },
                    icon = { Text(tab.symbol) },
                    modifier = Modifier.testTag("tab-${tab.title}")
                )
            }
        }
    }
}

@Composable
private fun HomeTab(
    state: HomeUiState,
    runtimeStatus: AiRuntimeStatus,
    provisioningStatus: AiProvisioningStatus,
    onModelImport: (Uri) -> Unit,
    onSetUpPersonalAi: () -> Unit,
    onRememberOnce: (note: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var note by remember { mutableStateOf("") }

    LazyColumn(
        modifier = modifier.testTag("home-tab"),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { ScreenHeader() }
        item {
            AndroidBaselineCard(
                runtimeStatus = runtimeStatus,
                provisioningStatus = provisioningStatus,
                onSetUpPersonalAi = onSetUpPersonalAi,
                onModelImport = onModelImport
            )
        }
        item {
            MemoryRequestCard(
                note = note,
                onNoteChange = { note = it },
                onDeny = { note = "" },
                onAllowOnce = {
                    onRememberOnce(note)
                    note = ""
                }
            )
        }
        item { SectionTitle("Local audit trail") }

        when (state) {
            Loading -> item {
                Text(
                    text = "Loading local memory...",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            is Error -> item {
                Text(
                    text = "Local memory is unavailable. No cloud fallback was used.",
                    color = MaterialTheme.colorScheme.error
                )
            }
            is Success -> {
                if (state.data.isEmpty()) {
                    item { EmptyMemoryCard() }
                } else {
                    items(state.data) { memory ->
                        MemoryCard(memory = memory)
                    }
                }
            }
        }
    }
}

@Composable
private fun ChatTab(
    messages: List<ChatMessage>,
    runtimeStatus: AiRuntimeStatus,
    onSendChat: (message: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var message by remember { mutableStateOf("") }

    LazyColumn(
        modifier = modifier.testTag("chat-tab"),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            HeaderBlock(
                title = "Chat",
                body = runtimeChatCopy(runtimeStatus)
            )
        }

        if (messages.isEmpty()) {
            item {
                Panel {
                    Text(
                        text = "Start a private chat",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Try: hi, I feel stuck, help me plan today, write a clearer message, or explain local memory.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            items(messages) { chatMessage ->
                ChatBubble(message = chatMessage)
            }
        }

        item {
            OutlinedTextField(
                value = message,
                onValueChange = { message = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("chat-message-input"),
                minLines = 2,
                label = { Text("Message") },
                placeholder = { Text("Tell Hapo Ndani what you need.") }
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = {
                    onSendChat(message)
                    message = ""
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("chat-send-button"),
                enabled = message.isNotBlank()
            ) {
                Text("Send")
            }
        }
    }
}

@Composable
private fun JournalTab(
    onJournalSave: (entry: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var entry by remember { mutableStateOf("") }

    LazyColumn(
        modifier = modifier.testTag("journal-tab"),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            HeaderBlock(
                title = "Journal",
                body = "Write first. Reflection should stay local, and weak phone models should not pretend to be ready."
            )
        }
        item {
            OutlinedTextField(
                value = entry,
                onValueChange = { entry = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("journal-entry-input"),
                minLines = 9,
                label = { Text("Private journal") },
                placeholder = { Text("What is taking up space today?") }
            )
        }
        item {
            Button(
                onClick = {
                    onJournalSave(entry)
                    entry = ""
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("journal-save-button"),
                enabled = entry.isNotBlank()
            ) {
                Text("Save locally")
            }
        }
        item {
            Panel {
                Text(
                    text = "Reflection readiness",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "Android reflection uses Gemma 3n E2B LiteRT-LM after runtime and device checks pass. E4B remains optional for stronger phones.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun ScreenHeader() {
    HeaderBlock(
        title = "Hapo Ndani",
        body = "Private journal, chat, and memory on Android. Local-first by default; no token API, analytics, or hosted inference is configured."
    )
}

@Composable
private fun HeaderBlock(title: String, body: String) {
    Column(
        modifier = Modifier.padding(top = 18.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = body,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun AndroidBaselineCard(
    runtimeStatus: AiRuntimeStatus,
    provisioningStatus: AiProvisioningStatus,
    onSetUpPersonalAi: () -> Unit,
    onModelImport: (Uri) -> Unit
) {
    val modelPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
        onResult = { uri -> uri?.let(onModelImport) }
    )

    Panel {
        Text(
            text = "Personal AI setup",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = provisioningStatus.messageForUser(),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        StatusLine(label = "Status", value = provisioningStatusLabel(provisioningStatus))
        StatusLine(label = "Runtime", value = runtimeStatusLabel(runtimeStatus))
        StatusLine(label = "Privacy", value = "Runs locally after setup; no hosted inference SDK")
        Button(
            onClick = onSetUpPersonalAi,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("model-auto-setup-button")
        ) {
            Text("Set up personal AI")
        }
        OutlinedButton(
            onClick = { modelPicker.launch(arrayOf("application/octet-stream", "*/*")) },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("model-import-button")
        ) {
            Text("Choose model file")
        }
    }
}

@Composable
private fun MemoryRequestCard(
    note: String,
    onNoteChange: (String) -> Unit,
    onDeny: () -> Unit,
    onAllowOnce: () -> Unit
) {
    Panel {
        Text(
            text = "Memory request",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = "Save one note to this device. The permission is scoped to this one note.",
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        OutlinedTextField(
            value = note,
            onValueChange = onNoteChange,
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
            label = { Text("Private memory") },
            placeholder = { Text("Example: Remember that invoices should be drafted locally first.") }
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = onDeny) {
                Text("Deny")
            }
            Button(
                onClick = onAllowOnce,
                enabled = note.isNotBlank()
            ) {
                Text("Allow once")
            }
        }
    }
}

@Composable
private fun ChatBubble(message: ChatMessage) {
    val container = if (message.role == ChatRole.User) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val startPadding = if (message.role == ChatRole.User) 48.dp else 0.dp
    val endPadding = if (message.role == ChatRole.User) 0.dp else 48.dp

    Card(
        colors = CardDefaults.cardColors(containerColor = container),
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = startPadding, end = endPadding)
    ) {
        Text(
            text = message.content,
            modifier = Modifier.padding(14.dp),
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold
    )
}

@Composable
private fun StatusLine(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun EmptyMemoryCard() {
    Panel {
        Text(
            text = "No local memories yet",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = "The first proof is simple: save a note only after an explicit permission decision.",
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun MemoryCard(memory: LocalMemory) {
    Panel {
        Text(
            text = memory.note,
            style = MaterialTheme.typography.bodyLarge
        )
        Text(
            text = "${memory.permission} - Stored on this device",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

private fun runtimeStatusLabel(runtimeStatus: AiRuntimeStatus): String =
    when (runtimeStatus) {
        is AiRuntimeStatus.MissingModel -> "Missing .litertlm file"
        is AiRuntimeStatus.Found -> "Model found, waiting for first load"
        is AiRuntimeStatus.Ready -> "LiteRT-LM ready"
        is AiRuntimeStatus.LoadFailed -> "LiteRT-LM failed: ${runtimeStatus.detail}"
    }

private fun provisioningStatusLabel(provisioningStatus: AiProvisioningStatus): String =
    when (provisioningStatus) {
        is AiProvisioningStatus.Ready -> "Ready"
        is AiProvisioningStatus.Installing -> {
            val total = provisioningStatus.totalBytesToDownload
            if (total > 0L) {
                val percent = (100L * provisioningStatus.bytesDownloaded / total).coerceIn(0L, 100L)
                "Installing $percent%"
            } else {
                "Installing"
            }
        }
        is AiProvisioningStatus.WaitingForPlayDelivery -> "Downloading from Google Play"
        is AiProvisioningStatus.NeedsUserAction -> "Needs model setup"
    }

private fun AiProvisioningStatus.messageForUser(): String =
    when (this) {
        is AiProvisioningStatus.Ready -> "Your personal AI model is installed. Open Chat and start talking."
        is AiProvisioningStatus.Installing -> message
        is AiProvisioningStatus.WaitingForPlayDelivery -> message
        is AiProvisioningStatus.NeedsUserAction ->
            "After a Play purchase, the app will try to install the personal AI model automatically. For local testing, choose the model file once."
    }

private fun runtimeChatCopy(runtimeStatus: AiRuntimeStatus): String =
    when (runtimeStatus) {
        is AiRuntimeStatus.MissingModel ->
            "No local model is loaded yet. Chat will stay capture-first until Gemma 3n E2B LiteRT-LM is present on this Android device."
        is AiRuntimeStatus.Found ->
            "A local model file was found. The first reply will initialize LiteRT-LM on-device before responding."
        is AiRuntimeStatus.Ready ->
            "Private chat is running through the local LiteRT-LM model on this device."
        is AiRuntimeStatus.LoadFailed ->
            "The local model failed to load. Chat stays capture-first until the runtime passes."
    }

@Composable
private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content
        )
    }
}

private enum class AndroidTab(val title: String, val symbol: String) {
    Home("Home", "H"),
    Chat("Chat", "C"),
    Journal("Journal", "J")
}

@Preview(showBackground = true)
@Composable
private fun DefaultPreview() {
    MyApplicationTheme(darkTheme = true) {
        Surface(color = Color(0xFF0B0E0D)) {
            HomeScreen(
                state = Success(
                    listOf(
                        LocalMemory("Remember that pilot notes stay local.", "Allow once", 1L),
                        LocalMemory("Draft before sending anything external.", "Allow once", 2L)
                    )
                ),
                chatMessages = listOf(
                    ChatMessage(ChatRole.User, "hiii"),
                    ChatMessage(ChatRole.Assistant, HAPO_NDANI_WELCOME)
                ),
                runtimeStatus = AiRuntimeStatus.Ready("/data/user/0/biz.nibiashara.hapondani/no_backup/models/gemma-3n-E2B-it-int4.litertlm"),
                provisioningStatus = AiProvisioningStatus.Ready("Personal AI is installed on this device."),
                onModelImport = {},
                onSetUpPersonalAi = {},
                onRememberOnce = {},
                onJournalSave = {},
                onSendChat = {}
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 340)
@Composable
private fun EmptyPreview() {
    MyApplicationTheme(darkTheme = true) {
        Surface(color = Color(0xFF0B0E0D)) {
            HomeScreen(
                state = Success(emptyList()),
                chatMessages = emptyList(),
                runtimeStatus = AiRuntimeStatus.MissingModel(
                    modelNames = LiteRtLmConversationRuntime.MODEL_FILE_NAMES,
                    installLocations = listOf("/data/user/0/biz.nibiashara.hapondani/no_backup/models")
                ),
                provisioningStatus = AiProvisioningStatus.NeedsUserAction("Personal AI setup has not finished on this device."),
                onModelImport = {},
                onSetUpPersonalAi = {},
                onRememberOnce = {},
                onJournalSave = {},
                onSendChat = {}
            )
        }
    }
}
