# CHIP SDK — suppress missing javax.annotation warnings
-dontwarn javax.annotation.**

# Keep all CHIP SDK classes (JNI needs them)
-keep class chip.** { *; }
