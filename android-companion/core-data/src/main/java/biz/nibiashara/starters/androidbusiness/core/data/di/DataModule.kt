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

package biz.nibiashara.ndani.companion.core.data.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import biz.nibiashara.ndani.companion.core.data.LocalMemory
import biz.nibiashara.ndani.companion.core.data.HomeRepository
import biz.nibiashara.ndani.companion.core.data.DefaultHomeRepository
import javax.inject.Inject
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
interface DataModule {

    @Singleton
    @Binds
    fun bindsHomeRepository(
        homeRepository: DefaultHomeRepository
    ): HomeRepository
}

class FakeHomeRepository @Inject constructor() : HomeRepository {
    override val homes: Flow<List<LocalMemory>> = flowOf(fakeHomes)

    override suspend fun add(note: String, permission: String, createdAtMillis: Long) {
        throw NotImplementedError()
    }
}

val fakeHomes = listOf(
    LocalMemory("Remember that I prefer local-only recall for pilot notes.", "Allow once", 1_713_000_000_000),
    LocalMemory("Drafts can be saved, but sending always needs approval.", "Allow once", 1_713_000_100_000)
)
