# 书源帮助文档

---

## 一、规则语法

### 规则前缀

| 前缀 | 说明 | 示例 |
|------|------|------|
| `@css:` | CSS选择器（Jsoup风格） | `@css:div.book-list > li` |
| `@xpath:` | XPath选择器 | `@xpath://div[@class="book-list"]/ul/li` |
| `@json:` | JSONPath | `@json:$.data.list` |
| `@js:` | 执行JavaScript，自动选择引擎 | `@js:result.match(/xxx/)` |
| `@rhino:` | 强制使用Rhino引擎执行JS | `@rhino:java.get(url)` |
| `@quickjs:` | 强制使用QuickJS引擎执行JS | `@quickjs:const x = 1;` |
| `@java:` | Java互操作（路由到Rhino引擎） | `@java:java.get(url)` |
| `@ts:` | TypeScript语法（编译后QuickJS执行） | `@ts:const x: number = 1;` |
| `@webjs:` | WebView JS模式 | `@webjs:document.title` |
| `<js>...</js>` | JS标签语法，等价于 `@js:` | `<js>result.match(/xxx/)</js>` |
| `:` | JS简写，冒号开头直接写JS代码 | `:result.match(/xxx/)` |

### 规则链接

使用 `@` 分隔多个规则步骤，前一步的输出作为后一步的输入：

```
class.book-item@tag.a@text
```

组合操作符：
- `&&` 交集：`tag.h3@text&&tag.a@text`
- `||` 或集
- `%%` 交错合并

### 正则替换

使用 `##` 分隔规则和正则替换表达式：

```
tag.p@text##作者：
```

多个替换规则用 `##` 分隔，支持捕获组：

```
tag.p@text##^\[([^\]]+)\]$##$1
```

### 模板变量

在URL和规则中使用 `{{expression}}` 插入动态值：

| 变量 | 说明 |
|------|------|
| `{{key}}` | 搜索关键字 |
| `{{page}}` | 当前页码 |
| `{{page+1}}` | 页码+1 |
| `{{result}}` | 上一步的结果 |
| `{{host}}` | 当前URL的域名 |
| `{{变量名}}` | 从变量系统获取值，未找到则尝试作为JS执行 |

### 引擎自动识别

使用 `@js:` 前缀时，系统自动识别引擎：

- 含ES6特征（`const`/`let`/`=>`/`async`/`await`/`class`/模板字符串）→ **QuickJS**
- 含 `java.` 调用且无ES6特征 → **Rhino**
- 无法确定 → 使用书源 `engine` 字段或默认 **QuickJS**

---

## 二、JS 内置变量

JS执行时自动注入以下变量，可直接使用：

### 基础变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `result` | String | 当前规则处理的结果（HTML/JSON/文本） |
| `baseUrl` | String | 当前页面的基础URL |
| `content` | String | `result` 的别名 |
| `src` | String | `result` 的别名 |
| `title` | String | 章节标题（`chapter.title` 的快捷方式） |
| `index` | Number | 章节索引（仅在正文规则中可用） |

### source 对象（书源元数据）

| 属性 | 类型 | 说明 |
|------|------|------|
| `source.bookSourceUrl` | String | 书源URL |
| `source.bookSourceName` | String | 书源名称 |
| `source.bookSourceGroup` | String | 书源分组 |
| `source.bookSourceType` | Number | 书源类型（0文字/1音频/2图片/3文件/4视频） |
| `source.header` | String | 请求头JSON字符串 |
| `source.loginUrl` | String | 登录URL |
| `source.loginCheckJs` | String | 登录检查JS |
| `source.enabledCookieJar` | Boolean | 是否启用CookieJar |
| `source.concurrentRate` | String | 并发频率限制 |
| `source.jsLib` | String | JS库代码 |
| `source.variable` | String | 书源变量（JSON字符串，需 `JSON.parse` 后使用） |

### book 对象（书籍信息）

| 属性 | 别名 | 说明 |
|------|------|------|
| `book.name` | `book.bookName` | 书名 |
| `book.author` | `book.bookAuthor` | 作者 |
| `book.bookUrl` | | 书籍URL |
| `book.coverUrl` | | 封面URL |
| `book.intro` | | 简介 |
| `book.kind` | | 分类 |
| `book.lastChapter` | | 最新章节 |
| `book.tocUrl` | | 目录URL |
| `book.wordCount` | | 字数 |

### chapter 对象（章节信息）

| 属性 | 别名 | 说明 |
|------|------|------|
| `chapter.title` | | 章节标题 |
| `chapter.url` | `chapter.chapterUrl` | 章节URL |
| `chapter.index` | `chapter.chapterIndex` | 章节序号 |
| `chapter.isVolume` | | 是否为卷 |

### cookie 对象

| 属性 | 说明 |
|------|------|
| `cookie` | 当前请求的Cookie信息（Object） |

### 使用示例

```javascript
<js>
// 获取书源变量
var vars = JSON.parse(source.variable || "{}");
var token = vars.token || "";

// 使用书籍信息
var bookName = book.name;
var author = book.author;

// 使用baseUrl拼接URL
var fullUrl = baseUrl + "/api/chapter";
</js>
```

---

## 三、java 桥接对象

### HTTP 请求

| 方法 | 说明 |
|------|------|
| `java.get(url, headers)` | HTTP GET请求，返回响应文本 |
| `java.post(url, body, headers)` | HTTP POST请求，返回响应文本 |
| `java.ajax(url, headers)` | 同 `java.get`，Legado兼容写法 |
| `java.ajaxAll(urls)` | 并发HTTP请求 |
| `java.getStrResponse(url, ruleStr)` | 请求URL并对结果应用规则解析 |

### 变量存取

| 方法 | 说明 |
|------|------|
| `java.put(key, value)` | 存储键值对到内存缓存 |
| `java.getStr(key, defaultValue)` | 从内存缓存读取值 |
| `java.getString(str, ruleStr)` | 对字符串应用规则解析（支持 `@css:` 前缀） |
| `java.getJson(str)` | 解析JSON字符串为对象 |
| `java.putJson(key, value)` | 以JSON格式存储值 |

### 加密/解密

| 方法 | 说明 |
|------|------|
| `java.aesEncode(data, key, iv)` | AES加密 |
| `java.aesDecode(data, key, iv)` | AES解密 |
| `java.md5Encode(str)` | MD5哈希 |
| `java.base64Encode(str)` | Base64编码 |
| `java.base64Decode(str)` | Base64解码 |
| `java.hexEncodeToString(str)` | 十六进制编码 |
| `java.hexDecodeToString(hex)` | 十六进制解码 |

### HTML 解析 (java.jsoup)

| 方法 | 说明 |
|------|------|
| `java.jsoup.parse(html)` | 解析HTML，返回带select方法的对象 |
| `java.jsoup.select(html, selector)` | CSS选择器选择所有元素 |
| `java.jsoup.selectFirst(html, selector)` | CSS选择器选择第一个元素 |
| `java.jsoup.getAttr(html, selector, attr)` | 获取元素属性值 |
| `java.jsoup.clean(html)` | 清理HTML标签 |

### 正则操作 (java.regex)

| 方法 | 说明 |
|------|------|
| `java.regex.match(str, pattern)` | 正则匹配第一个结果 |
| `java.regex.matchAll(str, pattern)` | 正则匹配所有结果（返回数组） |
| `java.regex.replace(str, pattern, replacement)` | 正则替换 |
| `java.regex.test(str, pattern)` | 正则测试（返回Boolean） |

### 时间/编码工具

| 方法 | 说明 |
|------|------|
| `java.timeFormat(timestamp, format)` | 时间戳格式化 |
| `java.getTime()` | 获取当前时间戳（毫秒） |
| `java.encodeURI(str)` | URI编码（encodeURIComponent） |

### 缓存管理 (java.cache)

| 方法 | 说明 |
|------|------|
| `java.cache.get(key)` | 从缓存读取 |
| `java.cache.put(key, value)` | 写入缓存 |
| `java.cache.delete(key)` | 删除缓存条目 |

### 日志

| 方法 | 说明 |
|------|------|
| `java.log(msg)` | 输出日志到控制台（调试页面可见） |

### WebView (java.webview)

| 方法 | 说明 |
|------|------|
| `java.webview.eval(url, js)` | 在WebView中执行JS（占位） |

### 使用示例

```javascript
<js>
// HTTP请求
var html = java.get("https://example.com/api");

// 带请求头
var resp = java.get(url, {"User-Agent": "Mozilla/5.0"});

// POST请求
var result = java.post(url, "key=value", {
  "Content-Type": "application/x-www-form-urlencoded"
});

// Jsoup解析
var name = java.jsoup.selectFirst(html, "h1.title");
var links = java.jsoup.select(html, "a.chapter");

// 正则匹配
var match = java.regex.match(html, /<h1>(.*?)<\/h1>/);
var all = java.regex.matchAll(html, /<a href="(.*?)"/g);

// 加密
var encrypted = java.aesEncode(data, key, iv);
var md5 = java.md5Encode("hello");
var b64 = java.base64Encode("hello");

// 缓存
java.cache.put("token", "abc123");
var token = java.cache.get("token");

// 日志
java.log("调试信息: " + result);
</js>
```

---

## 四、CryptoJS 加密库

全局注入 `CryptoJS` 对象，兼容Legado书源加密写法。

### AES 加密/解密

| 方法 | 说明 |
|------|------|
| `CryptoJS.AES.encrypt(data, key, cfg)` | AES加密，cfg可含 iv/mode/padding |
| `CryptoJS.AES.decrypt(data, key, cfg)` | AES解密 |

### 哈希

| 方法 | 说明 |
|------|------|
| `CryptoJS.MD5(str)` | MD5哈希 |
| `CryptoJS.HmacSHA256(data, key)` | HMAC-SHA256 |
| `CryptoJS.SHA256(data)` | SHA-256 |
| `CryptoJS.SHA1(data)` | SHA-1 |

### 编码器 (CryptoJS.enc)

| 方法 | 说明 |
|------|------|
| `CryptoJS.enc.Utf8.parse(s)` | UTF-8字符串 → WordArray |
| `CryptoJS.enc.Utf8.stringify(w)` | WordArray → UTF-8字符串 |
| `CryptoJS.enc.Base64.parse(s)` | Base64字符串 → WordArray |
| `CryptoJS.enc.Base64.stringify(w)` | WordArray → Base64字符串 |
| `CryptoJS.enc.Hex.parse(s)` | 十六进制字符串 → WordArray |
| `CryptoJS.enc.Hex.stringify(w)` | WordArray → 十六进制字符串 |

### 加密模式 (CryptoJS.mode)

| 常量 | 说明 |
|------|------|
| `CryptoJS.mode.ECB` | ECB模式 |
| `CryptoJS.mode.CBC` | CBC模式（默认） |

### 填充模式 (CryptoJS.pad)

| 常量 | 说明 |
|------|------|
| `CryptoJS.pad.Pkcs7` | PKCS7填充（默认） |
| `CryptoJS.pad.ZeroPadding` | 零填充 |
| `CryptoJS.pad.NoPadding` | 无填充 |

### 使用示例

```javascript
<js>
// AES-CBC加密
var key = CryptoJS.enc.Utf8.parse("1234567890123456");
var iv = CryptoJS.enc.Utf8.parse("1234567890123456");
var encrypted = CryptoJS.AES.encrypt("hello", key, {iv: iv});
var encStr = encrypted.toString();

// AES-CBC解密
var decrypted = CryptoJS.AES.decrypt(encStr, key, {iv: iv});
var decStr = CryptoJS.enc.Utf8.stringify(decrypted);

// AES-ECB加密
var key2 = CryptoJS.enc.Utf8.parse("1234567890123456");
var enc2 = CryptoJS.AES.encrypt("hello", key2, {
  mode: CryptoJS.mode.ECB
});

// MD5
var hash = CryptoJS.MD5("hello").toString();
</js>
```

---

## 五、变量系统

### @put / @get 规则语法

在规则中使用 `@put` 存储变量，用 `@get` 读取变量：

```
@put:{"token":"tag.span@text","id":"class.uid@attr(data-id)"}
```

```
@get:{token}
```

执行流程：
1. `@put:{...}` 中的每个值作为规则执行，结果存入变量
2. `@get:{key}` 从变量中读取值并替换

### 变量查找链（优先级从高到低）

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | 本地变量 | `@put` 存入的变量，当前规则链内有效 |
| 2 | 书源变量 | `source.variable`（JSON字符串，持久化存储） |
| 3 | 书源快捷属性 | `bookSourceUrl` / `bookSourceName` / `bookSourceGroup` |
| 4 | 书籍快捷属性 | `name` / `bookName` / `author` / `bookAuthor` / `bookUrl` / `coverUrl` / `intro` / `kind` / `lastChapter` / `tocUrl` / `wordCount` |
| 5 | 章节快捷属性 | `title` / `chapterUrl` / `chapterIndex` / `isVolume` |

### source.variable 持久化

书源的 `variable` 字段是JSON字符串，可跨请求持久化：

```javascript
// JS中读写source.variable
var vars = JSON.parse(source.variable || "{}");
vars.token = "new_token";
java.put("variable", JSON.stringify(vars));
```

### java.put / java.getStr 内存缓存

`java.put`/`java.getStr` 是内存级缓存，仅在当前书源会话内有效：

```javascript
java.put("key", "value");
var val = java.getStr("key", "default");
```

### java.cache 持久化缓存

`java.cache` 通过SharedPreferences持久化，跨会话有效：

```javascript
java.cache.put("token", "abc123");
var token = java.cache.get("token");
java.cache.delete("token");
```

### {{expression}} 模板变量

在URL和规则中，`{{}}` 内的表达式按以下顺序解析：

1. **变量查找** — 先从变量查找链中搜索
2. **规则执行** — 以 `@`/`$.`/`//`/`$[` 开头的表达式作为规则执行
3. **JS执行** — 其他表达式作为JavaScript代码执行

```
https://api.com/search?keyword={{key}}&page={{page}}
https://api.com/detail?id={{$.data.id}}
```

### jsLib 共享作用域

书源的 `jsLib` 字段支持两种格式：

**纯JS代码** — 执行后结果存为 `_jsLib` 变量，所有规则可访问

**JSON Map** — 每个 key 对应一个变量：

```json
{
  "util": "https://example.com/util.js",
  "config": "var config = {timeout: 5000};"
}
```

规则中可直接使用 `util` 和 `config` 变量。

---

## 六、URL 选项

### URL选项语法

在URL后添加 `,{选项JSON}` 来配置请求参数：

```
https://example.com/search,{"method":"POST","body":"key={{key}}"}
```

### 请求选项

| 选项 | 说明 |
|------|------|
| `method` | 请求方法：GET / POST（默认GET） |
| `body` | POST请求体字符串 |
| `headers` | 自定义请求头（JSON字符串或Object） |
| `charset` | 响应编码，如 `"gbk"` |
| `webView` | 是否使用WebView加载（Boolean） |
| `js` | URL级JS脚本，请求前/后执行 |
| `bodyJs` | 响应体JS转换脚本 |
| `retry` | 重试次数（默认0） |

### 发现地址格式

`exploreUrl` 支持多行格式，每行一个分类，使用 `::` 分隔分类名和URL：

```
推荐::https://example.com/recommend
热门::https://example.com/hot
更新::https://example.com/update
```

### 搜索URL格式

`searchUrl` 支持模板变量和页码：

```
https://example.com/search?key={{key}}&page={{page}}
```

POST搜索：

```
https://example.com/search,{"method":"POST","body":"keyword={{key}}&page={{page}}"}
```

### URL中的JS

搜索/发现URL支持 `@js:` 前缀动态生成：

```javascript
@js:
var url = "https://api.com/search";
var body = JSON.stringify({keyword: key, page: page});
url + ",{\"method\":\"POST\",\"body\":\"" + encodeURIComponent(body) + "\"}"
```

### 请求头格式

`header` 字段为JSON字符串：

```json
{"User-Agent": "Mozilla/5.0", "Referer": "https://example.com"}
```

### 规则执行位置

不同规则字段在书源流程中的执行时机：

| 字段 | 执行时机 |
|------|---------|
| `searchUrl` | 搜索时生成搜索URL |
| `checkKeyWord` | 搜索结果返回后校验关键词 |
| `bookList` | 从搜索/发现页面提取书籍列表 |
| `bookInfo.init` | 详情页加载后预处理（JS初始化） |
| `preUpdateJs` | 目录更新前执行的JS |
| `formatJs` | 章节列表格式化JS |
| `contentRule.js` | 正文加载后执行的JS |
| `callBackJs` | 内容回调JS |
| `loginCheckJs` | 登录状态检查JS |
