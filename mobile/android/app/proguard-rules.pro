# Keep rules for the release build's R8 pass.
#
# Flutter itself is mostly native, but plugins reach into Java/Kotlin classes by
# reflection, which R8 cannot see and will happily strip.

# Flutter embedding and plugin registration.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Our own platform-channel surface: MainActivity's method/event channels and the
# home-screen widget provider are both instantiated by the framework, not by us.
-keep class com.santim.santim.** { *; }

# flutter_secure_storage -> androidx.security.crypto -> Tink, which resolves key
# templates reflectively.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class androidx.security.crypto.** { *; }

# local_auth's biometric prompt.
-keep class androidx.biometric.** { *; }

# sqflite and path_provider both bind through the standard plugin registry,
# which the io.flutter.plugins rule above already covers. Nothing extra needed.

# Strip Android log calls from release builds - they are debug aids, and a
# finance app should not be narrating balances into logcat.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
