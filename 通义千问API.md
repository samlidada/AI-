模型名称：Pro/Qwen/Qwen2.5-VL-7B-Instruct
硅基流动API 文档链接：https://docs.siliconflow.cn/cn/api-reference/chat-completions/chat-completions
APIKEY：sk-ymyhdfwdhgkksjnakhrimqgdfxpebirmpwemkkrkejcjnben

调用实例
curl --request POST \
  --url https://api.siliconflow.cn/v1/chat/completions \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '{
  "model": "Qwen/QwQ-32B",
  "messages": [
    {
      "role": "user",
      "content": "What opportunities and challenges will the Chinese large model industry face in 2025?"
    }
  ],
  "stream": false,
  "max_tokens": 512,
  "stop": null,
  "temperature": 0.7,
  "top_p": 0.7,
  "top_k": 50,
  "frequency_penalty": 0.5,
  "n": 1,
  "response_format": {
    "type": "text"
  },
  "tools": [
    {
      "type": "function",
      "function": {
        "description": "<string>",
        "name": "<string>",
        "parameters": {},
        "strict": false
      }
    }
  ]
}'

返回示例：
{
  "id": "<string>",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "<string>",
        "reasoning_content": "<string>",
        "tool_calls": [
          {
            "id": "<string>",
            "type": "function",
            "function": {
              "name": "<string>",
              "arguments": "<string>"
            }
          }
        ]
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 123,
    "completion_tokens": 123,
    "total_tokens": 123
  },
  "created": 123,
  "model": "<string>",
  "object": "chat.completion"
}

## 多模态调用示例

以下是发送包含图片和文本的请求示例：

```json
{
  "model": "Qwen2.5-VL-7B-Instruct",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "这个图片展示了什么？"
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAoHBwkHBgoJCAkLCwoMDxkQDw4ODx4WFxIZJCAmJSMgIyIoLTkwKCo2KyIjMkQyNjs9QEBAJjBGS0U+Sjk/QD3/2wBDAQsLCw8NDx0QEB09KSMpPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT3/wAARCAAKAAoDASIAAhEBAxEB/8QAFwAAAwEAAAAAAAAAAAAAAAAAAAMGB//EACMQAAIBAwMFAQAAAAAAAAAAAAECAwQFEQASIQYTMTJBUWH/xAAUAQEAAAAAAAAAAAAAAAAAAAAE/8QAGBEAAwEBAAAAAAAAAAAAAAAAAAECEQP/2gAMAwEAAhEDEQA/ANDuF9tlPZaG5GqWW1VHdSZj3A0Y24bA5G0jzkHxqndLlb7hEkE8qxoZEkLP6MrBlJ+wQQfOpnVdrWn6VtsUY2pJTFm+yzuT+5OgZ6i/n//Z"
          }
        }
      ]
    }
  ],
  "max_tokens": 512,
  "temperature": 0.7
}
```

使用多模态API调用时需要注意：

1. 使用支持视觉功能的模型，如`Qwen2.5-VL-7B-Instruct`
2. `content`字段需要是一个数组，每个元素包含不同类型的内容：
   - 文本内容：使用`{"type": "text", "text": "问题内容"}`
   - 图片内容：使用`{"type": "image_url", "image_url": {"url": "base64编码的图片数据"}}`
3. 图片数据需要转换为base64格式，并添加适当的MIME类型前缀
4. 为避免请求过大，建议限制图片大小并进行压缩处理
5. 每次请求中图片数量建议不超过3张，以确保响应速度
