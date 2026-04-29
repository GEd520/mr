# AI 调试服务接口文档

## 服务信息

- **WebSocket 地址**: `ws://localhost:9527`
- **HTTP API 地址**: `http://localhost:9527/api`
- **状态页面**: `http://localhost:9527/status`

## 连接方式

### WebSocket 连接

```javascript
const ws = new WebSocket('ws://localhost:9527');

ws.onopen = () => {
  console.log('已连接到调试服务');
};

ws.onmessage = (event) => {
  const response = JSON.parse(event.data);
  console.log('收到响应:', response);
};

ws.onerror = (error) => {
  console.error('连接错误:', error);
};
```

### HTTP API 调用

```bash
curl -X POST http://localhost:9527/api \
  -H "Content-Type: application/json" \
  -d '{"type": "ping", "id": "1", "data": {}}'
```

## 消息格式

### 请求格式

```json
{
  "type": "命令类型",
  "id": "请求ID",
  "data": {
    // 命令参数
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### 响应格式

```json
{
  "id": "请求ID",
  "success": true,
  "result": {
    // 返回数据
  },
  "error": null,
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### 错误响应

```json
{
  "id": "请求ID",
  "success": false,
  "result": null,
  "error": "错误信息",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## 可用命令

### 1. ping - 心跳测试

**请求**:

```json
{
  "type": "ping",
  "id": "1",
  "data": {}
}
```

**响应**:

```json
{
  "id": "1",
  "success": true,
  "result": {
    "pong": true
  }
}
```

### 2. test\_search - 测试搜索

**请求**:

```json
{
  "type": "test_search",
  "id": "2",
  "data": {
    "source": {
      "bookSourceUrl": "https://example.com",
      "bookSourceName": "示例书源",
      "searchUrl": "https://example.com/search?key={{key}}",
      "ruleSearch": {
        "bookList": "class.book-list@tag.li",
        "name": "tag.h3@text",
        "author": "tag.p@text##作者：",
        "bookUrl": "tag.a@href"
      }
    },
    "keyword": "斗破苍穹"
  }
}
```

**响应**:

```json
{
  "id": "2",
  "success": true,
  "result": {
    "keyword": "斗破苍穹",
    "count": 10,
    "results": [
      {
        "name": "斗破苍穹",
        "author": "天蚕土豆",
        "bookUrl": "https://example.com/book/123"
      }
    ]
  }
}
```

### 3. test\_explore - 测试发现

**请求**:

```json
{
  "type": "test_explore",
  "id": "3",
  "data": {
    "source": {
      "bookSourceUrl": "https://example.com",
      "bookSourceName": "示例书源",
      "exploreUrl": "全部::https://example.com/list/all",
      "ruleExplore": {
        "bookList": "class.book-item",
        "name": "tag.h2@text",
        "author": "tag.p@text",
        "bookUrl": "tag.a@href"
      }
    },
    "url": "https://example.com/list/all"
  }
}
```

### 4. test\_book\_info - 测试书籍信息

**请求**:

```json
{
  "type": "test_book_info",
  "id": "4",
  "data": {
    "source": {
      "bookSourceUrl": "https://example.com",
      "ruleBookInfo": {
        "name": "tag.h1@text",
        "author": "class.author@text",
        "intro": "class.intro@text",
        "tocUrl": "class.read-btn@href"
      }
    },
    "bookUrl": "https://example.com/book/123"
  }
}
```

### 5. test\_toc - 测试目录

**请求**:

```json
{
  "type": "test_toc",
  "id": "5",
  "data": {
    "source": {
      "bookSourceUrl": "https://example.com",
      "ruleToc": {
        "chapterList": "class.chapter-list@tag.li",
        "chapterName": "tag.a@text",
        "chapterUrl": "tag.a@href"
      }
    },
    "bookUrl": "https://example.com/book/123"
  }
}
```

### 6. test\_content - 测试正文

**请求**:

```json
{
  "type": "test_content",
  "id": "6",
  "data": {
    "source": {
      "bookSourceUrl": "https://example.com",
      "ruleContent": {
        "content": "class.content@html"
      }
    },
    "chapterUrl": "https://example.com/chapter/123"
  }
}
```

### 7. test\_rule - 测试规则

**请求**:

```json
{
  "type": "test_rule",
  "id": "7",
  "data": {
    "content": "<html><body><div class=\"book-list\"><li><h3>书名</h3></li></div></body></html>",
    "rule": "class.book-list@tag.li@tag.h3@text",
    "ruleType": "string"
  }
}
```

**ruleType 可选值**:

- `string`: 返回字符串
- `list`: 返回列表
- `map`: 返回对象列表
- `auto`: 自动判断（默认）

### 8. execute\_js - 执行 JavaScript

**请求**:

```json
{
  "type": "execute_js",
  "id": "8",
  "data": {
    "code": "const items = result.match(/<li[^>]*>(.*?)<\\/li>/g) || []; JSON.stringify(items);",
    "variables": {
      "result": "<ul><li>项目1</li><li>项目2</li></ul>"
    }
  }
}
```

### 9. get\_book\_sources - 获取书源列表

**请求**:

```json
{
  "type": "get_book_sources",
  "id": "9",
  "data": {}
}
```

### 10. add\_book\_source - 添加书源

**请求**:

```json
{
  "type": "add_book_source",
  "id": "10",
  "data": {
    "source": {
      "bookSourceUrl": "https://newsource.com",
      "bookSourceName": "新书源",
      "enabled": true
    }
  }
}
```

### 11. update\_book\_source - 更新书源

**请求**:

```json
{
  "type": "update_book_source",
  "id": "11",
  "data": {
    "source": {
      "bookSourceUrl": "https://example.com",
      "bookSourceName": "更新后的书源名",
      "enabled": false
    }
  }
}
```

### 12. delete\_book\_source - 删除书源

**请求**:

```json
{
  "type": "delete_book_source",
  "id": "12",
  "data": {
    "sourceUrl": "https://example.com"
  }
}
```

### 13. get\_miniprograms - 获取小程序列表

**请求**:

```json
{
  "type": "get_miniprograms",
  "id": "13",
  "data": {}
}
```

### 14. get\_plugins - 获取插件列表

**请求**:

```json
{
  "type": "get_plugins",
  "id": "14",
  "data": {}
}
```

### 15. http\_request - 发送 HTTP 请求

**请求**:

```json
{
  "type": "http_request",
  "id": "15",
  "data": {
    "url": "https://example.com/api/data",
    "method": "GET",
    "headers": {
      "User-Agent": "Mozilla/5.0",
      "Authorization": "Bearer token"
    },
    "body": null
  }
}
```

## 规则语法参考

### CSS 选择器

```
class.book-list          // class选择器
tag.div                  // 标签选择器
class.book-list@tag.li   // 子元素选择
tag.h3@text              // 获取文本
tag.a@href               // 获取属性
tag.p.0@text             // 获取第一个p标签的文本
tag.p.-1@text            // 获取最后一个p标签的文本
```

### JSONPath

```
$.data.list              // 获取data.list
$.data.books             // 获取data.books数组
$.name                   // 获取name字段
$.data.list.*.name       // 获取list数组中所有name
```

### XPath

```
//div[@class='book-list']/ul/li    // 选择li元素
.//h3/a/text()                     // 获取文本
.//a/@href                         // 获取href属性
```

### 正则表达式

```
<h3[^>]*>([^<]*)<\/h3>             // 匹配h3标签内容
作者[：:]([^<]*)                    // 匹配作者信息
```

### JavaScript

```
:result.match(/name":"([^"]*)"/)?.[1] || ''
:const items = result.match(/<li[^>]*>[\s\S]*?<\/li>/g) || []; JSON.stringify(items);
```

## 使用示例

### Python 客户端示例

```python
import websocket
import json

def on_message(ws, message):
    response = json.loads(message)
    print(f"收到响应: {response}")

def on_error(ws, error):
    print(f"错误: {error}")

def on_open(ws):
    # 测试搜索
    request = {
        "type": "test_search",
        "id": "1",
        "data": {
            "source": {
                "bookSourceUrl": "https://example.com",
                "bookSourceName": "示例书源",
                "searchUrl": "https://example.com/search?key={{key}}",
                "ruleSearch": {
                    "bookList": "class.book-list@tag.li",
                    "name": "tag.h3@text",
                    "author": "tag.p@text##作者：",
                    "bookUrl": "tag.a@href"
                }
            },
            "keyword": "斗破苍穹"
        }
    }
    ws.send(json.dumps(request))

ws = websocket.WebSocketApp(
    "ws://localhost:9527",
    on_open=on_open,
    on_message=on_message,
    on_error=on_error
)
ws.run_forever()
```

### Node.js 客户端示例

```javascript
const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:9527');

ws.on('open', () => {
  // 测试搜索
  const request = {
    type: 'test_search',
    id: '1',
    data: {
      source: {
        bookSourceUrl: 'https://example.com',
        bookSourceName: '示例书源',
        searchUrl: 'https://example.com/search?key={{key}}',
        ruleSearch: {
          bookList: 'class.book-list@tag.li',
          name: 'tag.h3@text',
          author: 'tag.p@text##作者：',
          bookUrl: 'tag.a@href'
        }
      },
      keyword: '斗破苍穹'
    }
  };
  ws.send(JSON.stringify(request));
});

ws.on('message', (data) => {
  const response = JSON.parse(data);
  console.log('收到响应:', response);
});
```

## 调试流程建议

1. **测试搜索规则**
   - 先用 `test_search` 测试搜索功能
   - 检查返回的书籍列表是否正确
2. **测试书籍信息规则**
   - 从搜索结果中获取 `bookUrl`
   - 用 `test_book_info` 测试书籍详情
3. **测试目录规则**
   - 用 `test_toc` 测试目录解析
   - 检查章节列表是否完整
4. **测试正文规则**
   - 从目录中获取 `chapterUrl`
   - 用 `test_content` 测试正文解析
5. **调试规则**
   - 如果规则不工作，用 `test_rule` 单独测试
   - 可以先用 `http_request` 获取原始HTML
   - 再用 `test_rule` 测试规则匹配
6. **保存书源**
   - 所有测试通过后，用 `add_book_source` 保存

