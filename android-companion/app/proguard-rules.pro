# Hapo Ndani — ProGuard / R8 rules for release builds
# Keep line numbers for crash reports
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ──────────────────────────────────────────────
# Hilt / Dagger
# ──────────────────────────────────────────────
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }
-keep,allowobfuscation,allowshrinking @dagger.hilt.android.EarlyEntryPoint class *
-keep @dagger.hilt.InstallIn class *
-keep @dagger.hilt.android.lifecycle.HiltViewModel class * { *; }
-keep @dagger.Module class * { *; }
-keep @dagger.hilt.EntryPoint class * { *; }
-keepclasseswithmembers class * {
    @dagger.* <methods>;
}
-keepclasseswithmembers class * {
    @javax.inject.* <fields>;
    @javax.inject.* <init>(...);
}

# ──────────────────────────────────────────────
# Room
# ──────────────────────────────────────────────
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao interface * { *; }
-keepclassmembers @androidx.room.Entity class * {
    <fields>;
}
-keep class biz.nibiashara.ndani.companion.core.database.** { *; }

# ──────────────────────────────────────────────
# SQLCipher
# ──────────────────────────────────────────────
-keep class net.zetetic.database.** { *; }
-keep class net.zetetic.database.sqlcipher.** { *; }

# ──────────────────────────────────────────────
# LiteRT-LM (native JNI bridge)
# ──────────────────────────────────────────────
-keep class com.google.ai.edge.litertlm.** { *; }
-keepclassmembers class com.google.ai.edge.litertlm.** {
    native <methods>;
    <init>(...);
}

# ──────────────────────────────────────────────
# Google Play Asset Delivery
# ──────────────────────────────────────────────
-keep class com.google.android.play.core.** { *; }

# ──────────────────────────────────────────────
# Kotlin / Coroutines
# ──────────────────────────────────────────────
-keepclassmembers class kotlinx.coroutines.** { *; }
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlin.coroutines.** { *; }

# ──────────────────────────────────────────────
# App data classes used with sealed interfaces
# ──────────────────────────────────────────────
-keep class biz.nibiashara.ndani.companion.feature.home.ui.AiRuntimeStatus$* { *; }
-keep class biz.nibiashara.ndani.companion.feature.home.ui.AiRuntimeReply$* { *; }
-keep class biz.nibiashara.ndani.companion.feature.home.ui.AiProvisioningStatus$* { *; }
-keep class biz.nibiashara.ndani.companion.feature.home.ui.ChatMessage { *; }
-keep class biz.nibiashara.ndani.companion.feature.home.ui.HomeUiState$* { *; }
-keep class biz.nibiashara.ndani.companion.core.data.LocalMemory { *; }

# ──────────────────────────────────────────────
# Navigation (kotlinx.serialization for routes)
# ──────────────────────────────────────────────
-keepattributes *Annotation*
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}
