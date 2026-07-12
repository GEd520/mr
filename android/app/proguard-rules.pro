# Flutter 引擎核心类（必须保留，R8 不应裁剪）
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }

# Flutter Play Store Split (不需要但R8会检查)
-dontwarn com.google.android.play.core.**

# Hive (Hive 不依赖 protobuf，无需 keep GeneratedMessageLite)
-dontwarn com.google.protobuf.**

# Rhino JS引擎 (Android没有java.beans包)
-dontwarn java.beans.**
-dontwarn org.mozilla.javascript.JavaToJSONConverters

# 以下库 R8 在 fullMode 下可自动分析使用情况，无需保守 keep：
# - Dio：HTTP 客户端，R8 能跟踪
# - Okio：同上
# - 序列化：fromJson/toJson 通过反射调用，必须保留
-keepclassmembers class * {
    *** fromJson(...);
    *** toJson(...);
}