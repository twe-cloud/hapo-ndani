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

package biz.nibiashara.ndani.companion.core.data

import biz.nibiashara.ndani.companion.core.database.Home
import biz.nibiashara.ndani.companion.core.database.HomeDao
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class LocalMemory(
    val note: String,
    val permission: String,
    val createdAtMillis: Long
)

interface HomeRepository {
    val homes: Flow<List<LocalMemory>>

    suspend fun add(note: String, permission: String, createdAtMillis: Long)
}

class DefaultHomeRepository @Inject constructor(
    private val homeDao: HomeDao
) : HomeRepository {

    override val homes: Flow<List<LocalMemory>> =
        homeDao.getHomes().map { items ->
            items.map {
                LocalMemory(
                    note = it.note,
                    permission = it.permission,
                    createdAtMillis = it.createdAtMillis
                )
            }
        }

    override suspend fun add(note: String, permission: String, createdAtMillis: Long) {
        homeDao.insertHome(
            Home(
                note = note,
                permission = permission,
                createdAtMillis = createdAtMillis
            )
        )
    }
}
