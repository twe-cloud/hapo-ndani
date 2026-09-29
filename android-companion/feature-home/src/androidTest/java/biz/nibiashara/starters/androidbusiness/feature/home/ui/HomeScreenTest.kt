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

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import biz.nibiashara.ndani.companion.core.data.LocalMemory
import biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState.Success
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HomeScreenTest {

    @get:Rule
    val composeTestRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun homeShowsAndroidBaselineAndLocalMemory() {
        setHomeContent()

        composeTestRule.onNodeWithText("Hapo Ndani").assertExists()
        composeTestRule.onNodeWithText("Personal AI setup").assertExists()
        composeTestRule.onNodeWithText("Needs model setup").assertExists()
        composeTestRule.onNodeWithText("Set up personal AI").assertExists()
        composeTestRule
            .onNodeWithTag("home-tab")
            .performScrollToNode(hasText(FAKE_DATA.first().note))
        composeTestRule.onNodeWithText(FAKE_DATA.first().note).assertExists()
        composeTestRule.onNodeWithText("Allow once - Stored on this device").assertExists()
    }

    @Test
    fun tabsExposeHomeChatJournal() {
        setHomeContent()

        composeTestRule.onNodeWithText("Home").assertExists()
        composeTestRule.onNodeWithText("Chat").assertExists().performClick()
        composeTestRule.onNodeWithText("Start a private chat").assertExists()
        composeTestRule.onNodeWithText("Journal").assertExists().performClick()
        composeTestRule.onNodeWithText("Private journal").assertExists()
    }

    @Test
    fun chatSendEmitsSingleWelcomeForGreeting() {
        val sentMessages = mutableListOf<String>()
        setHomeContent(onSendChat = sentMessages::add)

        composeTestRule.onNodeWithText("Chat").performClick()
        composeTestRule.onNodeWithTag("chat-message-input").performTextInput("hiii")
        composeTestRule.onNodeWithTag("chat-send-button").performClick()

        assertEquals(listOf("hiii"), sentMessages)
    }

    @Test
    fun journalSaveEmitsLocalEntry() {
        val savedEntries = mutableListOf<String>()
        setHomeContent(onJournalSave = savedEntries::add)

        composeTestRule.onNodeWithText("Journal").performClick()
        composeTestRule.onNodeWithTag("journal-entry-input").performTextInput("Today felt workable.")
        composeTestRule.onNodeWithTag("journal-save-button").performClick()

        assertEquals(listOf("Today felt workable."), savedEntries)
    }

    private fun setHomeContent(
        state: HomeUiState = Success(FAKE_DATA),
        chatMessages: List<ChatMessage> = emptyList(),
        runtimeStatus: AiRuntimeStatus = AiRuntimeStatus.MissingModel(
            modelNames = LiteRtLmConversationRuntime.MODEL_FILE_NAMES,
            installLocations = listOf("/data/user/0/biz.nibiashara.hapondani/no_backup/models")
        ),
        provisioningStatus: AiProvisioningStatus = AiProvisioningStatus.NeedsUserAction(
            "Personal AI setup has not finished on this device."
        ),
        onRememberOnce: (String) -> Unit = {},
        onJournalSave: (String) -> Unit = {},
        onSendChat: (String) -> Unit = {}
    ) {
        composeTestRule.setContent {
            HomeScreen(
                state = state,
                chatMessages = chatMessages,
                runtimeStatus = runtimeStatus,
                provisioningStatus = provisioningStatus,
                onModelImport = {},
                onSetUpPersonalAi = {},
                onRememberOnce = onRememberOnce,
                onJournalSave = onJournalSave,
                onSendChat = onSendChat
            )
        }
    }
}

private val FAKE_DATA = listOf(
    LocalMemory("Remember that pilot notes stay local.", "Allow once", 1L)
)
