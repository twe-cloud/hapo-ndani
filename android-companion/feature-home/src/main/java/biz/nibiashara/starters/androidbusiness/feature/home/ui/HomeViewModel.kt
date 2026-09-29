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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import biz.nibiashara.ndani.companion.core.data.HomeRepository
import biz.nibiashara.ndani.companion.core.data.LocalMemory
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Error
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Loading
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Success
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

const val HAPO_NDANI_WELCOME =
    "Welcome to Hapo Ndani. I can help you think through plans, write, journal, and keep useful memory on this device. What are you trying to work on?"

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val homeRepository: HomeRepository,
    private val aiRuntime: AiConversationRuntime
) : ViewModel() {

    val uiState: StateFlow<HomeUiState> = homeRepository
        .homes.map<List<LocalMemory>, HomeUiState> { Success(data = it) }
        .catch { emit(Error(it)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), Loading)

    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages
    val runtimeStatus: StateFlow<AiRuntimeStatus> = aiRuntime.status
    val provisioningStatus: StateFlow<AiProvisioningStatus> = aiRuntime.provisioningStatus

    init {
        viewModelScope.launch {
            try {
                aiRuntime.provisionAutomatically()
            } catch (_: Exception) {
                // Provisioning failed silently; UI will show NeedsUserAction state
            }
        }
    }

    fun rememberOnce(note: String) {
        val trimmedNote = note.trim()
        if (trimmedNote.isEmpty()) return

        viewModelScope.launch {
            homeRepository.add(
                note = trimmedNote,
                permission = "Allow once",
                createdAtMillis = System.currentTimeMillis()
            )
        }
    }

    fun saveJournalEntry(entry: String) {
        val trimmedEntry = entry.trim()
        if (trimmedEntry.isEmpty()) return

        viewModelScope.launch {
            homeRepository.add(
                note = trimmedEntry,
                permission = "Journal local",
                createdAtMillis = System.currentTimeMillis()
            )
        }
    }

    fun importModel(uri: Uri) {
        viewModelScope.launch {
            try {
                aiRuntime.importModel(uri)
            } catch (_: Exception) {
                // Import failed; runtime status flow will reflect the error state
            }
        }
    }

    fun setUpPersonalAi() {
        viewModelScope.launch {
            try {
                aiRuntime.provisionAutomatically()
            } catch (_: Exception) {
                // Provisioning failed; status flow will reflect the error state
            }
        }
    }

    fun sendChatMessage(message: String) {
        val trimmedMessage = message.trim()
        if (trimmedMessage.isEmpty()) return

        _chatMessages.update { current ->
            current + ChatMessage(ChatRole.User, trimmedMessage) +
                ChatMessage(ChatRole.Assistant, "Checking the local model...")
        }

        viewModelScope.launch {
            val response = try {
                when (val reply = aiRuntime.generate(trimmedMessage)) {
                    is AiRuntimeReply.Generated -> reply.text
                    is AiRuntimeReply.MissingModel -> missingModelMessage(reply.status)
                    is AiRuntimeReply.Failed -> loadFailedMessage(reply.status)
                }
            } catch (_: Exception) {
                "The personal AI model could not respond right now. Try again, or go to Home to check model setup."
            }
            replaceLastAssistantMessage(response)
        }
    }

    companion object {
        fun missingModelMessage(status: AiRuntimeStatus.MissingModel): String =
            "Personal AI is still setting up on this device. On the Play build, that should happen automatically after purchase. For this test build, go to Home, choose the E2B model file, then come back here."

        fun loadFailedMessage(status: AiRuntimeStatus.LoadFailed): String =
            if (status.detail.contains("emulator", ignoreCase = true)) {
                "The E2B model is installed, but this emulator cannot run it safely. I am staying in capture mode here; test the conversation on an 8 GB+ physical Android phone."
            } else {
                "The personal AI model did not start on this device. I am staying in capture mode instead of pretending to chat."
            }

        fun localFirstResponse(prompt: String): String {
            val normalized = prompt
                .trim()
                .lowercase()
                .filter { it.isLetterOrDigit() || it.isWhitespace() }
                .split(Regex("\\s+"))
                .filter { it.isNotBlank() }
                .joinToString(" ")
            val compact = normalized.replace(" ", "")

            return when {
                normalized in directGreetings || isGreetingLike(compact) -> HAPO_NDANI_WELCOME
                normalized.containsAny("device troubleshooting assistant", "dead battery", "dead power button") ->
                    "I'm Hapo Ndani, not a device repair bot. Tell me what you want to work on, and I will help with private planning, writing, journaling, or memory."
                normalized.containsAny("feel stuck", "overwhelmed", "tired", "anxious", "lost") ->
                    "Start with the pressure, not perfect wording. Name the one thing taking up the most space, then we can sort it into decide, do, defer, or let go."
                normalized.containsAny("plan my day", "plan today", "prioritize", "todo", "to do", "next step") ->
                    "Give me the messy list. I will help turn it into one must-do, one useful next step, and what to ignore for now."
                normalized.containsAny("write", "draft", "rewrite", "email", "message") ->
                    "Paste the rough version or tell me the audience, tone, and goal. I can help make it clearer, shorter, warmer, or more direct."
                normalized.containsAny("memory", "remember", "journal") ->
                    "Hapo Ndani keeps memory local. Use it for recurring context, journal reflections, decisions, and patterns you want future chats to remember."
                normalized.containsAny("ship", "launch", "product", "business", "customer") ->
                    "Tell me what you are trying to ship and what is blocking it. I will help separate product, customer, trust, and next-action issues."
                normalized.containsAny("model", "llm", "ai responsiveness", "conversation quality") ->
                    "The Android floor should be Gemma 3n E2B through LiteRT-LM for broad 8 GB Android support. E4B can be an optional high-quality mode on stronger phones."
                normalized.length <= 40 && normalized.contains("what") && normalized.contains("do") -> HAPO_NDANI_WELCOME
                isLikelyKeyboardMash(normalized) ->
                    "I might not have caught that. Send it again, or tell me whether you want a plan, rewrite, reflection, or next step."
                else ->
                    "I hear you. Do you want help planning it, writing it, reflecting on it, or turning it into the next concrete step?"
            }
        }

        private val directGreetings = setOf(
            "hi",
            "hello",
            "hey",
            "yo",
            "sup",
            "start",
            "help",
            "get started",
            "how are you",
            "who are you",
            "what are you",
            "what can you do"
        )

        private fun String.containsAny(vararg markers: String): Boolean =
            markers.any { contains(it) }

        private fun isGreetingLike(compactPrompt: String): Boolean {
            if (compactPrompt.length > 24) return false
            if (compactPrompt in setOf("hello", "heloo", "helloo", "hey")) return true
            if (compactPrompt.firstOrNull() == 'h') {
                val rest = compactPrompt.drop(1)
                return rest.isNotEmpty() && rest.all { it == 'i' || it == 'e' || it == 'y' }
            }
            return compactPrompt.isNotEmpty() && compactPrompt.all { it == 'y' || it == 'o' }
        }

        private fun isLikelyKeyboardMash(normalized: String): Boolean {
            val words = normalized.split(" ").filter { it.isNotBlank() }
            if (words.size != 1) return false
            val word = words.single()
            if (word.length !in 6..16) return false
            val commonWords = setOf("because", "through", "people", "really", "should", "please", "thanks", "memory", "journal")
            if (word in commonWords) return false
            val vowelRatio = word.count { it in "aeiou" }.toDouble() / word.length.toDouble()
            return vowelRatio < 0.35 || listOf("fj", "jpc", "dsk", "mpo", "qz", "zx").any { word.contains(it) }
        }
    }

    private fun replaceLastAssistantMessage(response: String) {
        _chatMessages.update { current ->
            val lastAssistantIndex = current.indexOfLast { it.role == ChatRole.Assistant }
            if (lastAssistantIndex == -1) return@update current

            current.mapIndexed { index, chatMessage ->
                if (index == lastAssistantIndex) {
                    chatMessage.copy(content = response)
                } else {
                    chatMessage
                }
            }
        }
    }
}

sealed interface HomeUiState {
    object Loading : HomeUiState
    data class Error(val throwable: Throwable) : HomeUiState
    data class Success(val data: List<LocalMemory>) : HomeUiState
}

enum class ChatRole {
    User,
    Assistant
}

data class ChatMessage(
    val role: ChatRole,
    val content: String
)
