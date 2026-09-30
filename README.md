# 知汐

知汐是一个使用个人 DeepSeek API Key 的安卓文字聊天应用。首版只有一个会话，支持连续对话。

## 使用

1. 在项目目录运行 flutter pub get 和 flutter run，或构建安卓调试版 APK。
2. 打开右上角设置，输入自己的 DeepSeek API Key 并保存。
3. 返回聊天页发送消息。应用会把当前会话的文字消息发送给 DeepSeek，以便模型理解上下文。

API Key 保存在设备的安全存储中，不写入源码。聊天记录只在应用运行期间保留；关闭应用后不会保存聊天记录。可选 deepseek-flash 或 deepseek-v4-pro，并可开关深度思考及思考过程展示。DeepSeek API 当前不提供模型内置联网搜索。

安卓包名暂为 com.example.zhixi，发布前应改为自己的唯一包名。
