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

package biz.nibiashara.ndani.companion.data

import biz.nibiashara.ndani.companion.core.data.DefaultHomeRepository
import biz.nibiashara.ndani.companion.core.database.Home
import biz.nibiashara.ndani.companion.core.database.HomeDao
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DefaultHomeRepositoryTest {

    @Test
    fun homes_newMemorySaved_memoryIsReturned() = runTest {
        val repository = DefaultHomeRepository(FakeHomeDao())

        repository.add(
            note = "Remember this locally.",
            permission = "Allow once",
            createdAtMillis = 42L
        )

        val memory = repository.homes.first().single()
        assertEquals("Remember this locally.", memory.note)
        assertEquals("Allow once", memory.permission)
        assertEquals(42L, memory.createdAtMillis)
    }
}

private class FakeHomeDao : HomeDao {

    private val data = mutableListOf<Home>()

    override fun getHomes(): Flow<List<Home>> = flow {
        emit(data)
    }

    override suspend fun insertHome(item: Home) {
        data.add(0, item)
    }
}
