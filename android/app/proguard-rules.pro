# JNI entry points are looked up by name from native code.
-keep class com.echo.whisper.WhisperContext { native <methods>; }
-keep class com.echo.llm.LlmSession { native <methods>; }
