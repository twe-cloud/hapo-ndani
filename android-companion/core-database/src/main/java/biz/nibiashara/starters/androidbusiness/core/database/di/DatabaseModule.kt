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

package biz.nibiashara.ndani.companion.core.database.di

import android.content.Context
import androidx.room.Room
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import biz.nibiashara.ndani.companion.core.database.AppDatabase
import biz.nibiashara.ndani.companion.core.database.HomeDao
import net.zetetic.database.sqlcipher.SupportOpenHelperFactory
import java.io.File
import java.security.SecureRandom
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
class DatabaseModule {
    @Provides
    fun provideHomeDao(appDatabase: AppDatabase): HomeDao {
        return appDatabase.homeDao()
    }

    @Provides
    @Singleton
    fun provideAppDatabase(@ApplicationContext appContext: Context): AppDatabase {
        val passphrase = getOrCreateDatabaseKey(appContext)
        val factory = SupportOpenHelperFactory(passphrase)
        return Room.databaseBuilder(
            appContext,
            AppDatabase::class.java,
            "ndani-local-memory"
        )
            .openHelperFactory(factory)
            .fallbackToDestructiveMigration()
            .build()
    }

    private fun getOrCreateDatabaseKey(context: Context): ByteArray {
        val keyFile = File(context.noBackupFilesDir, ".ndani_db_key")
        try {
            if (keyFile.exists() && keyFile.length() == 32L) {
                return keyFile.readBytes()
            }
        } catch (_: Exception) {
            // Key file corrupted or unreadable; generate a new one
        }
        val passphrase = ByteArray(32)
        SecureRandom().nextBytes(passphrase)
        keyFile.parentFile?.mkdirs()
        try {
            keyFile.writeBytes(passphrase)
        } catch (_: Exception) {
            // Key file write failed; use in-memory key (data won't persist across restarts)
        }
        return passphrase
    }
}
