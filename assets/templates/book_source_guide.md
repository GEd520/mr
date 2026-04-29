# 书源规则编写指南

## 一、书源基础信息

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| bookSourceUrl | String | 是 | 书源地址，作为书源唯一标识 |
| bookSourceName | String | 是 | 书源名称 |
| bookSourceGroup | String | 否 | 书源分组 |
| bookSourceType | Int | 否 | 类型：0=小说, 1=音频, 2=图片, 3=文件, 4=视频 |
| enabled | Bool | 否 | 是否启用，默认true |
| enabledExplore | Bool | 否 | 是否启用发现，默认true |
| header | String | 否 | 请求头，JSON格式 |
| searchUrl | String | 否 | 搜索地址，支持变量 {{key}} {{page}} |
| exploreUrl | String | 否 | 发现地址，格式：名称::URL，多个用换行分隔 |
| jsLib | String | 否 | 公共JS库，可在规则中调用 |
| bookSourceComment | String | 否 | 书源说明 |

## 二、URL变量

在 searchUrl 和 exploreUrl 中可使用以下变量：

| 变量 | 说明 |
|------|------|
| {{key}} | 搜索关键词 |
| {{page}} | 页码 |
| {{host}} | 书源地址 |

示例：
```
"searchUrl": "https://example.com/search?key={{key}}&page={{page}}"
"exploreUrl": "全部::https://example.com/list/all\n玄幻::https://example.com/list/xuanhuan"
```

## 三、规则语法

### 3.1 规则类型前缀

| 前缀 | 说明 | 示例 |
|------|------|------|
| @css: | CSS选择器 | `@css:.book-list li` |
| @xpath: | XPath | `@xpath://div[@class='book']/a` |
| @json: | JSONPath | `@json:$.data.list` |
| @js: 或 : | JavaScript | `:result.match(/name":"([^"]*)"/)?.[1]` |
| 无前缀 | 自动判断 | 根据内容自动选择解析方式 |

### 3.2 CSS选择器语法

CSS选择器是最常用的规则类型，支持以下写法：

#### 基本选择器
```
class.book-list      // class选择器
tag.div              // 标签选择器
#book-id             // ID选择器（较少使用）
```

#### 属性获取
```
tag.a@href           // 获取href属性
tag.img@src          // 获取src属性
class.cover@data-url // 获取data-url属性
```

#### 文本获取
```
tag.h1@text          // 获取文本内容
tag.p@text           // 获取文本内容
class.intro@html     // 获取HTML内容
class.content@outerHtml // 获取包含自身的HTML
```

#### 子元素选择
```
class.book-list@tag.li           // 选择子元素li
class.book-info@tag.p.0          // 选择第一个p标签
class.book-info@tag.p.1          // 选择第二个p标签
class.book-info@tag.p.-1         // 选择最后一个p标签
```

#### 链式规则
使用 `##` 分隔多个规则步骤：
```
tag.p@text##作者：##作者:        // 获取文本后替换"作者："和"作者:"
class.intro@text##\\s+##        // 去除多余空白
```

### 3.3 JSONPath语法

用于解析JSON API返回的数据：

```
$.data.list           // 获取data.list数组
$.data.books          // 获取data.books数组
$.name                // 获取name字段
$.author              // 获取author字段
$.data.list.*.name    // 获取list数组中所有name字段
```

### 3.4 XPath语法

用于XML/HTML解析：

```
//div[@class='book-list']/ul/li    // 选择book-list下的li
.//h3/a/text()                     // 相对路径，获取文本
.//a/@href                         // 获取href属性
//div[@class='content']/html()     // 获取HTML内容
```

### 3.5 正则表达式

用于复杂文本匹配：

```
<h3[^>]*>([^<]*)<\/h3>              // 匹配h3标签内容
作者[：:]([^<]*)                     // 匹配作者信息
<img[^>]*src="([^"]*)"              // 匹配图片src
```

### 3.6 JavaScript规则

用于复杂逻辑处理：

```javascript
// 简单表达式
:result.match(/name":"([^"]*)"/)?.[1] || ''

// 复杂处理
:const items = result.match(/<li[^>]*>[\s\S]*?<\/li>/g) || [];
const books = items.map(item => ({
  name: item.match(/<h3>([^<]*)<\/h3>/)?.[1] || '',
  author: item.match(/作者：([^<]*)/)?.[1] || ''
}));
JSON.stringify(books);
```

## 四、搜索规则 (ruleSearch)

| 字段 | 说明 | 示例 |
|------|------|------|
| checkKeyWord | 校验关键词，用于验证搜索结果 | `data` |
| bookList | 书籍列表规则 | `class.book-list@tag.li` |
| name | 书名规则 | `tag.h3@text` |
| author | 作者规则 | `tag.p.0@text##作者：` |
| intro | 简介规则 | `class.intro@text` |
| kind | 分类规则 | `tag.span.0@text` |
| lastChapter | 最新章节规则 | `tag.a.1@text` |
| updateTime | 更新时间规则 | `tag.span.1@text` |
| bookUrl | 书籍详情URL规则 | `tag.a.0@href` |
| coverUrl | 封面URL规则 | `tag.img@src` |
| wordCount | 字数规则 | `tag.span.2@text` |

## 五、发现规则 (ruleExplore)

与搜索规则字段相同，用于发现页内容解析。

## 六、书籍信息规则 (ruleBookInfo)

| 字段 | 说明 | 示例 |
|------|------|------|
| init | 初始化规则，用于预处理页面 | `:js预处理代码` |
| name | 书名规则 | `tag.h1@text` |
| author | 作者规则 | `class.author@text##作者：` |
| intro | 简介规则 | `class.intro@text` |
| kind | 分类规则 | `class.category@text` |
| lastChapter | 最新章节规则 | `class.last-chapter@text` |
| updateTime | 更新时间规则 | `class.update-time@text` |
| coverUrl | 封面URL规则 | `tag.img@src` |
| tocUrl | 目录页URL规则 | `class.read-btn@href` |
| wordCount | 字数规则 | `class.word-count@text` |
| canReName | 是否可重命名 | `true` |
| downloadUrls | 下载地址规则 | `class.download@href` |

## 七、目录规则 (ruleToc)

| 字段 | 说明 | 示例 |
|------|------|------|
| preUpdateJs | 预处理JS | `:预处理代码` |
| chapterList | 章节列表规则 | `class.chapter-list@tag.li` |
| chapterName | 章节名称规则 | `tag.a@text` |
| chapterUrl | 章节URL规则 | `tag.a@href` |
| formatJs | 格式化JS | `:格式化代码` |
| isVolume | 是否为卷名规则 | `tag.span@text##卷` |
| isVip | 是否VIP章节规则 | `class.vip@text` |
| isPay | 是否付费章节规则 | `class.pay@text` |
| updateTime | 更新时间规则 | `tag.time@text` |
| nextTocUrl | 下一页目录URL规则 | `class.next-page@href` |

## 八、正文规则 (ruleContent)

| 字段 | 说明 | 示例 |
|------|------|------|
| content | 正文内容规则 | `class.content@html` |
| subContent | 备用正文规则 | `class.article@html` |
| title | 章节标题规则 | `tag.h1@text` |
| nextContentUrl | 下一页URL规则 | `class.next-page@href` |
| webJs | 网页JS执行 | `:JS代码` |
| sourceRegex | 资源正则 | `正则表达式` |
| replaceRegex | 替换正则 | `##<script[^>]*>.*?</script>##广告` |
| imageStyle | 图片样式 | `style="max-width:100%"` |
| imageDecode | 图片解码JS | `:解码代码` |
| payAction | 付费动作 | `:付费处理代码` |
| callBackJs | 回调JS | `:回调代码` |

## 九、完整示例

### 9.1 HTML网站书源

```json
{
  "bookSourceUrl": "https://www.example.com",
  "bookSourceName": "示例小说站",
  "bookSourceType": 0,
  "enabled": true,
  "searchUrl": "https://www.example.com/search.php?keyword={{key}}",
  "exploreUrl": "全部::https://www.example.com/category/all\n玄幻::https://www.example.com/category/xuanhuan",
  "ruleSearch": {
    "bookList": "class.grid@tag.li",
    "name": "tag.h3@tag.a@text",
    "author": "tag.p.0@text##作者：",
    "bookUrl": "tag.h3@tag.a@href"
  },
  "ruleBookInfo": {
    "name": "class.book-name@text",
    "author": "class.author@text##作者：",
    "intro": "class.intro@text",
    "tocUrl": "class.read-btn@href"
  },
  "ruleToc": {
    "chapterList": "class.chapter-list@tag.li",
    "chapterName": "tag.a@text",
    "chapterUrl": "tag.a@href"
  },
  "ruleContent": {
    "content": "class.content@html##<script[^>]*>.*?</script>"
  }
}
```

### 9.2 JSON API书源

```json
{
  "bookSourceUrl": "https://api.example.com",
  "bookSourceName": "API示例",
  "bookSourceType": 0,
  "header": "{\"Content-Type\": \"application/json\"}",
  "searchUrl": "https://api.example.com/v1/search?keyword={{key}}",
  "ruleSearch": {
    "bookList": "$.data.books",
    "name": "$.name",
    "author": "$.author",
    "bookUrl": "$.url"
  },
  "ruleBookInfo": {
    "name": "$.data.name",
    "author": "$.data.author",
    "intro": "$.data.intro"
  },
  "ruleToc": {
    "chapterList": "$.data.chapters",
    "chapterName": "$.title",
    "chapterUrl": "$.url"
  },
  "ruleContent": {
    "content": "$.data.content"
  }
}
```

## 十、调试技巧

1. **使用浏览器开发者工具**
   - F12打开开发者工具
   - 使用Elements面板检查HTML结构
   - 使用Console测试JavaScript代码

2. **规则测试顺序**
   - 先测试bookList规则是否正确获取列表
   - 再测试各个字段规则
   - 最后测试正文规则

3. **常见问题**
   - 编码问题：确保网站编码为UTF-8
   - 动态加载：可能需要使用JavaScript规则
   - 反爬虫：配置正确的header和cookie

4. **规则调试**
   - 使用`##`分隔多个替换规则
   - 使用正则表达式处理复杂情况
   - 使用JavaScript处理动态内容
