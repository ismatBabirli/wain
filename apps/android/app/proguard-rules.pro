# kotlinx.serialization keeps its generated serializers through its own rules;
# the wire types are read by name, so keep their companions.
-keepclassmembers @kotlinx.serialization.Serializable class com.wainhq.wain.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}

# Crash reports (store/Analytics.kt) name the exception and our own frames, read with no mapping file.
-keepattributes SourceFile,LineNumberTable
-keepnames class com.wainhq.wain.** { *; }
-keepnames class * extends java.lang.Throwable
