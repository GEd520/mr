# JS 书源开发完整文档

> 本文档详细说明 JS 书源开发中可用的所有 API、语法特性和内置对象。
> 本系统基于 QuickJS 引擎，支持 ES2020 几乎全部特性，你可以像写普通 JS 一样写书源！

---

## 一、双引擎对比：QuickJS vs Rhino

本系统内置两个 JS 引擎，根据代码特征自动分流，也可通过规则前缀手动指定。

### 1.1 引擎概览

| 特性 | QuickJS | Rhino |
|------|---------|-------|
| **实现语言** | C（flutter_js） | Java（Android原生） |
| **运行位置** | Flutter侧（Dart VM内） | Android侧（JVM内） |
| **JS标准** | ES2020 几乎全部 | ES5 + 部分ES6 |
| **执行模式** | 同步（evaluate） | 异步（MethodChannel） |
| **性能** | 快（C原生，无IPC开销） | 较慢（跨进程通信） |
| **Java互操作** | 通过桥接对象（java.*） | 直接调用Java类 |
| **适用场景** | 新书源、ES6+代码 | 兼容阅读3.0旧书源 |
| **指定前缀** | `@quickjs:` | `@rhino:` / `@java:` |
| **自动识别** | 含ES6特征时 | 含`java.`且无ES6时 |
| **默认引擎** | ✅ 是 | ❌ 否 |

### 1.2 JS 语法支持对比

| 语法特性 | QuickJS | Rhino | 示例 |
|----------|---------|-------|------|
| `var` | ✅ | ✅ | `var x = 1;` |
| `const` / `let` | ✅ | ❌ | `const x = 1; let y = 2;` |
| 箭头函数 | ✅ | ❌ | `(x) => x * 2` |
| 模板字符串 | ✅ | ❌ | `` `Hello ${name}` `` |
| 解构赋值 | ✅ | ❌ | `const {a, b} = obj;` |
| 展开运算符 `...` | ✅ | ❌ | `const arr2 = [...arr, 4]` |
| 剩余参数 | ✅ | ❌ | `function fn(...args) {}` |
| 默认参数 | ✅ | ❌ | `function fn(x = 10) {}` |
| `class` 类 | ✅ | ❌ | `class Foo {}` |
| `Promise` | ✅ | ❌ | `new Promise(...)` |
| `async` / `await` | ✅ | ❌ | `await fetch(url)` |
| `for...of` | ✅ | ❌ | `for (const x of arr) {}` |
| `Symbol` | ✅ | ❌ | `Symbol('key')` |
| `Map` / `Set` | ✅ | ❌ | `new Map(); new Set()` |
| `WeakMap` / `WeakSet` | ✅ | ❌ | `new WeakMap()` |
| `Proxy` / `Reflect` | ✅ | ❌ | `new Proxy(obj, h)` |
| `Generator` | ✅ | ❌ | `function* gen() { yield 1; }` |
| `BigInt` | ✅ | ❌ | `9007199254740991n` |
| 可选链 `?.` | ✅ | ❌ | `obj?.prop?.method?.()` |
| 空值合并 `??` | ✅ | ❌ | `null ?? 'default'` |
| `Object.entries/values` | ✅ | ❌ | `Object.keys(obj)` |
| `Array.from/of` | ✅ | ❌ | `Array.from({length:5})` |
| `Array.flatMap` | ✅ | ❌ | `arr.flatMap(x => [x])` |
| `String.includes` | ✅ | ❌ | `'hello'.includes('ell')` |
| `String.padStart` | ✅ | ❌ | `'5'.padStart(3, '0')` |
| `String.replaceAll` | ✅ | ❌ | `str.replaceAll('a','b')` |
| 正则命名捕获组 | ✅ | ❌ | `(?<name>\w+)` |
| 正则 dotAll | ✅ | ❌ | `/test/s` |
| 正则后行断言 | ✅ | ❌ | `(?<=\$)\d+` |
| `try...catch` 无参 | ✅ | ❌ | `try {} catch {}` |
| `Object.assign` | ✅ | ❌ | `Object.assign({}, obj)` |
| `Object.fromEntries` | ✅ | ❌ | `Object.fromEntries(arr)` |
| `for...in` | ✅ | ✅ | `for (k in obj) {}` |
| `Array.forEach/map/filter` | ✅ | ✅ | `arr.map(x => x*2)` |
| `Array.reduce/find` | ✅ | ✅ | `arr.reduce((a,b)=>a+b)` |
| `JSON.parse/stringify` | ✅ | ✅ | `JSON.parse(str)` |
| `Date` | ✅ | ✅ | `new Date()` |
| `Math` | ✅ | ✅ | `Math.floor(3.7)` |
| `RegExp` | ✅ | ✅ | `/pattern/g` |
| `parseInt/parseFloat` | ✅ | ✅ | `parseInt("10")` |
| `isNaN/isFinite` | ✅ | ✅ | `isNaN(NaN)` |

### 1.3 内置全局 API 对比

| 全局 API | QuickJS | Rhino | 说明 |
|----------|---------|-------|------|
| `fetch(url, options)` | ✅ | ❌ | HTTP请求（标准Web API） |
| `console.log/warn/error` | ✅ | ❌ | 控制台输出 |
| `console.dir/table/time` | ✅ | ❌ | 高级控制台方法 |
| `btoa()` / `atob()` | ✅ | ❌ | Base64编解码 |
| `setTimeout` / `setInterval` | ✅ | ❌ | 定时器 |
| `URL` / `URLSearchParams` | ✅ | ❌ | URL解析 |
| `XMLHttpRequest` | ✅ | ❌ | HTTP请求（兼容） |
| `require()` | ✅ | ❌ | 模块加载（简化） |
| `process` | ✅ | ❌ | Node.js process模拟 |
| `Buffer` | ✅ | ❌ | Node.js Buffer模拟 |
| `EventEmitter` | ✅ | ❌ | 事件发射器 |
| `CryptoJS` | ✅ | ❌ | 加密库（AES/MD5/SHA） |
| `java.*` 桥接 | ✅（缓存模式） | ✅（直接调用） | Java互操作 |
| `java.ajax()` | ✅（缓存优先） | ✅（真实请求） | HTTP GET |
| `java.jsoup.*` | ✅（桥接NativeChannel） | ✅（直接Jsoup） | HTML解析 |
| `java.aesEncode/Decode` | ✅（缓存优先） | ✅（真实加密） | AES加解密 |
| `java.md5Encode` | ✅（缓存优先） | ✅（真实哈希） | MD5哈希 |
| `java.put/getStr` | ✅（内存缓存） | ✅（内存缓存） | 变量存取 |
| `java.cache.*` | ✅（内存缓存） | ✅（SharedPreferences） | 持久化缓存 |
| `java.log()` | ✅（→console.log） | ✅（Log.d） | 日志输出 |
| `java.regex.*` | ✅（原生正则） | ✅（Java正则） | 正则操作 |
| `java.webview.eval` | ✅（占位） | ✅（占位） | WebView |
| `@css:` 规则 | ❌ | ✅ | CSS选择器规则 |
| `@text:` 规则 | ❌ | ✅ | 文本提取规则 |
| `@attr:` 规则 | ❌ | ✅ | 属性提取规则 |
| `java:类名` 反射 | ❌ | ✅ | Java类反射调用 |

### 1.4 HTTP 请求能力对比

| 能力 | QuickJS | Rhino |
|------|---------|-------|
| `fetch(url)` | ✅ 缓存优先 | ❌ |
| `java.get(url)` | ✅ 缓存优先 | ✅ OkHttp真实请求 |
| `java.post(url)` | ✅ 缓存优先 | ✅ OkHttp真实请求 |
| `java.ajax(url)` | ✅ 缓存优先 | ✅ OkHttp真实请求 |
| `java.ajaxAll(urls)` | ✅ 占位 | ✅ 并发请求 |
| `java.getStrResponse(url, rule)` | ✅ 缓存优先 | ✅ 请求+规则解析 |
| 带自定义请求头 | ✅ | ✅ |
| 超时设置 | ✅ | ✅ |
| HTTP缓存 | ✅ OkHttp Cache | ✅ OkHttp Cache |
| 文件下载 | ❌ | ✅ `httpDownload` |
| URL直接解析 | ❌ | ✅ `jsoupParseUrl` |
| 获取所有链接 | ❌ | ✅ `jsoupGetLinks` |

### 1.5 加密能力对比

| 能力 | QuickJS | Rhino |
|------|---------|-------|
| `CryptoJS.AES.encrypt/decrypt` | ✅（桥接NativeChannel） | ❌ |
| `CryptoJS.MD5` | ✅（桥接NativeChannel） | ❌ |
| `CryptoJS.SHA256/SHA1/HmacSHA256` | ✅（占位，返回空） | ❌ |
| `CryptoJS.enc.Utf8/Base64/Hex` | ✅ | ❌ |
| `CryptoJS.mode.ECB/CBC` | ✅ | ❌ |
| `CryptoJS.pad.Pkcs7/ZeroPadding/NoPadding` | ✅ | ❌ |
| `java.aesEncode/Decode` | ✅（缓存优先） | ✅（真实AES） |
| `java.md5Encode` | ✅（缓存优先） | ✅（真实MD5） |
| `java.base64Encode/Decode` | ✅（btoa/atob） | ✅（Android Base64） |
| `java.hexEncodeToString/Decode` | ✅（JS实现） | ❌ |
| AES-CBC/PKCS5Padding | ✅ | ✅ |
| AES-ECB/PKCS5Padding | ✅ | ✅ |
| AES-128 | ✅ | ✅ |

### 1.6 HTML 解析能力对比

| 能力 | QuickJS | Rhino |
|------|---------|-------|
| `java.jsoup.parse(html)` | ✅ | ✅ |
| `java.jsoup.select(html, css)` | ✅（桥接NativeChannel） | ✅（直接Jsoup） |
| `java.jsoup.selectFirst(html, css)` | ✅（桥接NativeChannel） | ✅（直接Jsoup） |
| `java.jsoup.getAttr(html, css, attr)` | ✅（桥接NativeChannel） | ✅（直接Jsoup） |
| `java.jsoup.clean(html)` | ✅（占位） | ✅（移除script/style/隐藏元素） |
| JS原生正则解析 | ✅ 推荐 | ✅ |
| JSON.parse | ✅ 推荐 | ✅ |

### 1.7 数据存储能力对比

| 能力 | QuickJS | Rhino |
|------|---------|-------|
| `java.put(key, value)` | ✅ 内存缓存 | ✅ 内存缓存 |
| `java.getStr(key)` | ✅ 内存缓存 | ✅ 内存缓存 |
| `java.cache.put(key, value)` | ✅ 内存缓存 | ✅ SharedPreferences |
| `java.cache.get(key)` | ✅ 内存缓存 | ✅ SharedPreferences |
| `java.cache.delete(key)` | ✅ 内存缓存 | ✅ SharedPreferences |
| `java.putJson(key, value)` | ✅ | ✅ |
| `java.getJson(str)` | ✅ | ✅ |
| `source.variable` | ✅ | ✅ |
| 跨会话持久化 | ❌（仅内存） | ✅（SharedPreferences） |

### 1.8 引擎选择建议

| 场景 | 推荐引擎 | 原因 |
|------|---------|------|
| 新写书源 | **QuickJS** | ES6+语法，标准Web API |
| 兼容阅读3.0旧书源 | **Rhino** | `java.*`直接调用，`@css:`规则 |
| 需要真实HTTP请求 | **Rhino** | QuickJS同步模式仅缓存 |
| 需要CryptoJS加密 | **QuickJS** | CryptoJS仅注入在QuickJS |
| 需要ES6+语法 | **QuickJS** | Rhino不支持 |
| 需要Jsoup解析 | **两者均可** | 都桥接到NativeChannel |
| 需要持久化存储 | **Rhino** | QuickJS仅内存缓存 |
| 网页加密代码直接用 | **QuickJS** | CryptoJS + btoa/atob |
| AI生成代码 | **QuickJS** | 标准JS语法，AI更熟悉 |

---

## 二、QuickJS 支持的 JS 语法（ES2020 全特性）

### 你可以直接用，不需要任何 `java.` 前缀！

| 特性 | 示例 | 说明 |
|------|------|------|
| **const / let** | `const x = 1; let y = 2;` | 块级作用域变量声明 |
| **箭头函数** | `const fn = (x) => x * 2;` | 简洁的函数写法 |
| **模板字符串** | `` `Hello ${name}` `` | 字符串插值 |
| **解构赋值** | `const {name, age} = obj;` | 对象/数组解构 |
| **展开运算符** | `const arr2 = [...arr1, 4]` | 数组/对象展开 |
| **剩余参数** | `function fn(...args) {}` | 可变参数 |
| **默认参数** | `function fn(x = 10) {}` | 参数默认值 |
| **class 类** | `class Foo { constructor() {} }` | 面向对象 |
| **Promise** | `new Promise((resolve) => resolve(1))` | 异步编程 |
| **async / await** | `const data = await fetch(url)` | 异步编程（同步模式下降级） |
| **for...of** | `for (const item of list) {}` | 迭代器遍历 |
| **Symbol** | `const sym = Symbol('key')` | 唯一标识符 |
| **Map / Set** | `const m = new Map(); m.set('k', 'v')` | 集合类型 |
| **WeakMap / WeakSet** | `const wm = new WeakMap()` | 弱引用集合 |
| **Proxy / Reflect** | `const p = new Proxy(obj, handler)` | 元编程 |
| **Generator** | `function* gen() { yield 1; }` | 生成器函数 |
| **Iterator** | `obj[Symbol.iterator] = function*() {}` | 自定义迭代器 |
| **BigInt** | `const big = 9007199254740991n` | 大整数 |
| **可选链** | `obj?.prop?.method?.()` | 安全访问 |
| **空值合并** | `const x = null ?? 'default'` | 空值回退 |
| **Object.entries/values/keys** | `Object.keys(obj)` | 对象遍历 |
| **Array.from/of** | `Array.from({length: 5}, (_, i) => i)` | 数组创建 |
| **Array.flatMap** | `[1,2,3].flatMap(x => [x, x*2])` | 映射+扁平化 |
| **String.includes/startsWith/endsWith** | `'hello'.includes('ell')` | 字符串方法 |
| **String.padStart/padEnd** | `'5'.padStart(3, '0')` | 字符串补齐 |
| **String.trimStart/trimEnd** | `'  hi  '.trimStart()` | 去空白 |
| **Object.assign/spread** | `const obj2 = {...obj1, x: 2}` | 对象合并 |
| **正则命名捕获组** | `/(?<year>\d{4})/` | 正则增强 |
| **正则 dotAll** | `/test/s` | `.` 匹配换行 |
| **正则后行断言** | `/(?<=\$)\d+/` | 向后断言 |
| **JSON.stringify 格式化** | `JSON.stringify(obj, null, 2)` | 格式化输出 |
| **try...catch 无参** | `try {} catch {}` | 省略 catch 参数 |

---

## 三、内置全局函数和对象（QuickJS 专属）

### 3.1 fetch() — HTTP 请求（标准 Web API）

```javascript
// GET 请求
var html = fetch("https://example.com/api");

// 带请求头
var html = fetch("https://example.com/api", {
  headers: { "User-Agent": "Mozilla/5.0" }
});

// POST 请求
var result = fetch("https://example.com/api", {
  method: "POST",
  body: "key=value",
  headers: { "Content-Type": "application/x-www-form-urlencoded" }
});
```

> **注意**：同步模式下 `fetch()` 优先从缓存获取。如果需要真实网络请求，请使用 `java.ajax()` 或在异步规则中使用。

### 3.2 console — 控制台（完整实现）

```javascript
console.log("Hello, 世界！");           // 普通日志
console.log("变量:", name, "值:", val);  // 多参数
console.warn("警告信息");               // 警告
console.error("错误信息");              // 错误
console.info("提示信息");               // 提示
console.debug("调试信息");              // 调试
console.dir(obj);                       // 打印对象结构
console.table(data);                    // 表格形式打印
console.time("请求");                   // 计时开始
console.timeEnd("请求");                // 计时结束，输出耗时
console.count("计数器");                // 计数
console.assert(x > 0, "x必须大于0");    // 断言
console.clear();                        // 清空日志
```

所有 `console.log` 输出都会同步到调试页面，你可以实时查看！

### 3.3 btoa / atob — Base64 编解码

```javascript
var encoded = btoa("Hello, 世界！");     // 编码
var decoded = atob(encoded);             // 解码
```

### 3.4 setTimeout / setInterval

```javascript
setTimeout(function() { /* 延迟执行 */ }, 1000);
setInterval(function() { /* 定时执行 */ }, 1000);
```

### 3.5 JSON — 原生支持

```javascript
var obj = JSON.parse('{"name":"test"}');  // 解析
var str = JSON.stringify(obj);            // 序列化
var pretty = JSON.stringify(obj, null, 2); // 格式化
```

### 3.6 Date — 日期时间

```javascript
var now = new Date();
var timestamp = Date.now();                // 毫秒时间戳
var formatted = now.toISOString();         // "2024-01-01T00:00:00.000Z"
var local = now.toLocaleString();          // 本地时间字符串
var year = now.getFullYear();
var month = now.getMonth() + 1;
var day = now.getDate();
var hours = now.getHours();
var minutes = now.getMinutes();
var seconds = now.getSeconds();
```

### 3.7 Math — 数学运算

```javascript
Math.floor(3.7);    // 3
Math.ceil(3.2);     // 4
Math.round(3.5);    // 4
Math.random();      // 0~1 随机数
Math.max(1, 2, 3);  // 3
Math.min(1, 2, 3);  // 1
Math.abs(-5);       // 5
Math.pow(2, 10);    // 1024
Math.sqrt(16);      // 4
Math.PI;            // 3.141592653589793
Math.E;             // 2.718281828459045
```

### 3.8 RegExp — 正则表达式（完整支持）

```javascript
// 基本正则
var match = result.match(/<h1>(.*?)<\/h1>/);

// 命名捕获组
var m = result.match(/(?<year>\d{4})-(?<month>\d{2})/);
var year = m.groups.year;

// 全局匹配
var all = result.matchAll(/<a href="(.*?)"/g);
for (const m of all) {
  console.log(m[1]);
}

// 替换
var text = result.replace(/<[^>]+>/g, "");

// 全部替换
var text = result.replaceAll("<br>", "\n");

// 测试
if (/^\d+$/.test(input)) { /* 是数字 */ }

// 动态正则
var pattern = new RegExp(keyword, "gi");
```

### 3.9 Array — 数组方法（ES6+ 全支持）

```javascript
var arr = [1, 2, 3, 4, 5];

arr.map(x => x * 2);                    // [2, 4, 6, 8, 10]
arr.filter(x => x > 2);                 // [3, 4, 5]
arr.reduce((sum, x) => sum + x, 0);     // 15
arr.find(x => x > 3);                   // 4
arr.findIndex(x => x > 3);              // 3
arr.some(x => x > 3);                   // true
arr.every(x => x > 0);                  // true
arr.includes(3);                         // true
arr.indexOf(3);                          // 2
arr.join(",");                           // "1,2,3,4,5"
arr.sort((a, b) => a - b);              // 升序
arr.reverse();                           // 反转
arr.slice(1, 3);                         // [2, 3]
arr.splice(1, 1);                        // 删除元素
arr.flatMap(x => [x, x * 2]);           // [1,2,2,4,3,6,4,8,5,10]
Array.from({length: 5}, (_, i) => i);   // [0,1,2,3,4]
Array.of(1, 2, 3);                       // [1,2,3]
[...arr, 6];                             // [1,2,3,4,5,6]
```

### 3.10 String — 字符串方法（ES6+ 全支持）

```javascript
var str = "Hello, World!";

str.includes("World");          // true
str.startsWith("Hello");        // true
str.endsWith("!");              // true
str.repeat(3);                  // "Hello, World!Hello, World!Hello, World!"
str.padStart(10, "0");          // "0Hello, Wo"
str.padEnd(15, ".");            // "Hello, World!.."
str.trim();                     // 去首尾空白
str.trimStart();                // 去首空白
str.trimEnd();                  // 去尾空白
str.replaceAll("o", "0");      // "Hell0, W0rld!"
str.substring(0, 5);            // "Hello"
str.slice(-6);                  // "orld!"
str.split(", ");                 // ["Hello", "World!"]
str.toUpperCase();               // "HELLO, WORLD!"
str.toLowerCase();               // "hello, world!"
str.charAt(0);                   // "H"
str.charCodeAt(0);               // 72
str.concat("!");                 // "Hello, World!!"
str.indexOf("World");            // 7
str.lastIndexOf("o");            // 8
str.match(/(\w+)/g);            // ["Hello", "World"]
str.search(/World/);            // 7
str.replace("World", "JS");     // "Hello, JS!"
```

### 3.11 Object — 对象方法（ES6+ 全支持）

```javascript
Object.keys(obj);               // 键数组
Object.values(obj);             // 值数组
Object.entries(obj);            // [key, value] 数组
Object.assign({}, obj);         // 浅拷贝
Object.fromEntries(entries);    // 从键值对创建对象
Object.freeze(obj);             // 冻结对象
Object.seal(obj);               // 密封对象
Object.is(a, b);                // 严格相等判断
Object.getOwnPropertyNames(obj); // 所有属性名
Object.getPrototypeOf(obj);     // 原型
const merged = {...obj1, ...obj2}; // 展开合并
```

### 3.12 Map / Set / WeakMap / WeakSet

```javascript
var m = new Map();
m.set("key", "value");
m.get("key");                   // "value"
m.has("key");                   // true
m.delete("key");
m.size;
m.clear();
for (const [k, v] of m) {}     // 遍历

var s = new Set([1, 2, 3, 2]);
s.add(4);
s.has(3);                       // true
s.delete(1);
s.size;
[...s];                         // [1, 2, 3, 4]
s.forEach(v => console.log(v));

var wm = new WeakMap();
wm.set(obj, "value");

var ws = new WeakSet();
ws.add(obj);
```

### 3.13 URL / URLSearchParams

```javascript
var url = new URL("https://example.com/path?q=test&page=1");
url.href;                       // 完整URL
url.protocol;                   // "https:"
url.hostname;                   // "example.com"
url.port;                       // ""
url.pathname;                   // "/path"
url.search;                     // "?q=test&page=1"
url.hash;                       // ""
url.searchParams.get("q");      // "test"
url.searchParams.set("page", "2");
url.searchParams.has("q");      // true
url.searchParams.delete("page");
url.toString();                  // 完整URL字符串

var params = new URLSearchParams();
params.set("key", "value");
params.append("tag", "1");
params.toString();               // "key=value&tag=1"
```

### 3.14 XMLHttpRequest（简化模拟）

```javascript
var xhr = new XMLHttpRequest();
xhr.open("GET", "https://example.com/api");
xhr.setRequestHeader("User-Agent", "Mozilla/5.0");
xhr.send();
var response = xhr.responseText;
var status = xhr.status;         // 200 或 0
```

### 3.15 require() — 模块加载（Node.js 兼容）

```javascript
var http = require('http');       // HTTP模拟
var https = require('https');     // HTTPS模拟
var fs = require('fs');           // 文件系统模拟
var path = require('path');       // 路径工具
var crypto = require('crypto');   // 加密模拟
var url = require('url');         // URL解析
var querystring = require('querystring'); // 查询字符串
var events = require('events');   // 事件
var stream = require('stream');   // 流
var util = require('util');       // 工具
var cheerio = require('cheerio'); // HTML解析模拟
```

> **注意**：这些模块是简化模拟，仅提供基础 API 兼容。推荐使用 `fetch()` + `java.jsoup` 替代。

### 3.16 process — Node.js process 模拟

```javascript
process.env;                     // 环境变量
process.argv;                    // 命令行参数
process.version;                 // "v18.17.0"
process.platform;                // "android"
process.cwd();                   // 当前目录
process.exit(0);                 // 退出
process.nextTick(fn);            // 下一个tick
```

### 3.17 Buffer — Node.js Buffer 模拟

```javascript
var buf = Buffer.from("hello");   // 从字符串创建
var buf2 = Buffer.from([1,2,3]); // 从数组创建
Buffer.isBuffer(obj);            // 判断是否Buffer
Buffer.concat([buf, buf2]);      // 合并
buf.toString();                   // 转字符串
buf.length;                       // 长度
```

---

## 四、书源 JS 内置变量（两个引擎通用）

JS 执行时自动注入以下变量，可直接使用：

### 4.1 基础变量

| 变量 | 类型 | QuickJS | Rhino | 说明 |
|------|------|---------|-------|------|
| `result` | String | ✅ | ✅ | 当前规则处理的结果（HTML/JSON/文本） |
| `baseUrl` | String | ✅ | ✅ | 当前页面的基础URL |
| `content` | String | ✅ | ✅ | `result` 的别名 |
| `src` | String | ✅ | ? | `result` 的别名 |
| `title` | String | ✅ | ? | 章节标题 |
| `index` | Number | ✅ | ? | 章节索引（正文规则中） |
| `html` | String | ❌ | ✅ | 页面HTML（Rhino别名） |

### 4.2 source 对象（书源元数据）

| 属性 | 类型 | QuickJS | Rhino | 说明 |
|------|------|---------|-------|------|
| `source.bookSourceUrl` | String | ✅ | ✅ | 书源URL |
| `source.bookSourceName` | String | ✅ | ✅ | 书源名称 |
| `source.bookSourceGroup` | String | ✅ | ✅ | 书源分组 |
| `source.bookSourceType` | Number | ✅ | ✅ | 类型（0文字/1音频/2图片/3文件/4视频） |
| `source.header` | String | ✅ | ✅ | 请求头JSON字符串 |
| `source.loginUrl` | String | ✅ | ✅ | 登录URL |
| `source.loginCheckJs` | String | ✅ | ✅ | 登录检查JS |
| `source.enabledCookieJar` | Boolean | ✅ | ✅ | 是否启用CookieJar |
| `source.concurrentRate` | String | ✅ | ✅ | 并发频率限制 |
| `source.jsLib` | String | ✅ | ✅ | JS库代码 |
| `source.variable` | String | ✅ | ✅ | 书源变量（JSON字符串） |

### 4.3 book 对象（书籍信息）

| 属性 | 别名 | QuickJS | Rhino | 说明 |
|------|------|---------|-------|------|
| `book.name` | `book.bookName` | ✅ | ✅ | 书名 |
| `book.author` | `book.bookAuthor` | ✅ | ✅ | 作者 |
| `book.bookUrl` | — | ✅ | ✅ | 书籍URL |
| `book.coverUrl` | — | ✅ | ✅ | 封面URL |
| `book.intro` | — | ✅ | ✅ | 简介 |
| `book.kind` | — | ✅ | ✅ | 分类 |
| `book.lastChapter` | — | ✅ | ✅ | 最新章节 |
| `book.tocUrl` | — | ✅ | ✅ | 目录URL |
| `book.wordCount` | — | ✅ | ✅ | 字数 |

### 4.4 chapter 对象（章节信息）

| 属性 | 别名 | QuickJS | Rhino | 说明 |
|------|------|---------|-------|------|
| `chapter.title` | — | ✅ | ✅ | 章节标题 |
| `chapter.url` | `chapter.chapterUrl` | ✅ | ✅ | 章节URL |
| `chapter.index` | `chapter.chapterIndex` | ✅ | ✅ | 章节序号 |
| `chapter.isVolume` | — | ✅ | ✅ | 是否为卷 |

### 4.5 cookie 对象

| 属性 | QuickJS | Rhino | 说明 |
|------|---------|-------|------|
| `cookie` | ✅ | ✅ | 当前请求的Cookie信息（Object） |

---

## 五、java 桥接对象（兼容层，两个引擎通用）

> `java.` 前缀是为了兼容阅读3.0书源。**新写的书源推荐直接用标准 JS API**，如 `fetch()`、`CryptoJS`、`console.log()` 等。

### 5.1 HTTP 请求

| 方法 | QuickJS | Rhino | 推荐替代 |
|------|---------|-------|---------|
| `java.get(url, headers)` | ✅ 缓存优先 | ✅ 真实请求 | `fetch(url)` |
| `java.post(url, body, headers)` | ✅ 缓存优先 | ✅ 真实请求 | `fetch(url, {method:"POST"})` |
| `java.ajax(url, headers)` | ✅ 缓存优先 | ✅ 真实请求 | `fetch(url)` |
| `java.ajaxAll(urls)` | ✅ 占位 | ✅ 并发请求 | — |
| `java.getStrResponse(url, ruleStr)` | ✅ 缓存优先 | ✅ 请求+规则 | — |

```javascript
// 以下三种写法等价：
var html = java.get("https://example.com/api");
var html = java.ajax("https://example.com/api");
var html = fetch("https://example.com/api");  // ← 推荐这种！
```

### 5.2 变量存取

| 方法 | QuickJS | Rhino | 说明 |
|------|---------|-------|------|
| `java.put(key, value)` | ✅ 内存缓存 | ✅ 内存缓存 | 存储键值对 |
| `java.getStr(key, defaultValue)` | ✅ 内存缓存 | ✅ 内存缓存 | 读取值 |
| `java.getString(str, ruleStr)` | ✅ | ✅ | 对字符串应用规则 |
| `java.getStrResponse(url, ruleStr)` | ✅ 缓存优先 | ✅ | 请求+规则 |
| `java.getJson(str)` | ✅ | ✅ | 解析JSON |
| `java.putJson(key, value)` | ✅ | ✅ | JSON存储 |

### 5.3 加密/解密

| 方法 | QuickJS | Rhino | 推荐替代 |
|------|---------|-------|---------|
| `java.aesEncode(data, key, iv)` | ✅ 缓存优先 | ✅ 真实加密 | `CryptoJS.AES.encrypt()` |
| `java.aesDecode(data, key, iv)` | ✅ 缓存优先 | ✅ 真实解密 | `CryptoJS.AES.decrypt()` |
| `java.md5Encode(str)` | ✅ 缓存优先 | ✅ 真实哈希 | `CryptoJS.MD5(str)` |
| `java.base64Encode(str)` | ✅ btoa | ✅ Android Base64 | `btoa(str)` |
| `java.base64Decode(str)` | ✅ atob | ✅ Android Base64 | `atob(str)` |
| `java.hexEncodeToString(str)` | ✅ JS实现 | ❌ | — |
| `java.hexDecodeToString(hex)` | ✅ JS实现 | ❌ | — |

### 5.4 HTML 解析 (java.jsoup)

| 方法 | QuickJS | Rhino | 说明 |
|------|---------|-------|------|
| `java.jsoup.parse(html)` | ✅ | ✅ | 解析HTML |
| `java.jsoup.select(html, selector)` | ✅ 桥接 | ✅ 直接 | CSS选择所有 |
| `java.jsoup.selectFirst(html, selector)` | ✅ 桥接 | ✅ 直接 | CSS选择首个 |
| `java.jsoup.getAttr(html, selector, attr)` | ✅ 桥接 | ✅ 直接 | 获取属性 |
| `java.jsoup.clean(html)` | ✅ 占位 | ✅ 真实清理 | 清理HTML |

### 5.5 正则操作 (java.regex)

| 方法 | QuickJS | Rhino | 推荐替代 |
|------|---------|-------|---------|
| `java.regex.match(str, pattern)` | ✅ | ✅ | `str.match(/pattern/)` |
| `java.regex.matchAll(str, pattern)` | ✅ | ✅ | `[...str.matchAll(/pattern/g)]` |
| `java.regex.replace(str, pattern, repl)` | ✅ | ✅ | `str.replace(/pattern/g, repl)` |
| `java.regex.test(str, pattern)` | ✅ | ✅ | `/pattern/.test(str)` |

### 5.6 时间/编码工具

| 方法 | QuickJS | Rhino | 推荐替代 |
|------|---------|-------|---------|
| `java.timeFormat(timestamp, format)` | ✅ | ✅ | `new Date(ts).toLocaleString()` |
| `java.getTime()` | ✅ | ✅ | `Date.now()` |
| `java.encodeURI(str)` | ✅ | ✅ | `encodeURIComponent(str)` |

### 5.7 缓存管理 (java.cache)

| 方法 | QuickJS | Rhino | 说明 |
|------|---------|-------|------|
| `java.cache.get(key)` | ✅ 内存 | ✅ SharedPreferences | 读取缓存 |
| `java.cache.put(key, value)` | ✅ 内存 | ✅ SharedPreferences | 写入缓存 |
| `java.cache.delete(key)` | ✅ 内存 | ✅ SharedPreferences | 删除缓存 |

### 5.8 日志

| 方法 | QuickJS | Rhino | 推荐替代 |
|------|---------|-------|---------|
| `java.log(msg)` | ✅ → console.log | ✅ → Log.d | `console.log(msg)` |

### 5.9 WebView

| 方法 | QuickJS | Rhino | 说明 |
|------|---------|-------|------|
| `java.webview.eval(url, js)` | ✅ 占位 | ✅ 占位 | WebView执行JS（未实现） |

---

## 六、CryptoJS 加密库（QuickJS 专属，直接用！）

> 全局注入 `CryptoJS` 对象，网页上的加密代码可以直接拷贝过来用！

### 6.1 AES 加密/解密

```javascript
// AES-CBC 加密
var key = CryptoJS.enc.Utf8.parse("1234567890123456");
var iv = CryptoJS.enc.Utf8.parse("1234567890123456");
var encrypted = CryptoJS.AES.encrypt("hello", key, {iv: iv});
var encStr = encrypted.toString();

// AES-CBC 解密
var decrypted = CryptoJS.AES.decrypt(encStr, key, {iv: iv});
var decStr = CryptoJS.enc.Utf8.stringify(decrypted);

// AES-ECB 加密
var key2 = CryptoJS.enc.Utf8.parse("1234567890123456");
var enc2 = CryptoJS.AES.encrypt("hello", key2, {
  mode: CryptoJS.mode.ECB
});
```

### 6.2 哈希

```javascript
var md5 = CryptoJS.MD5("hello").toString();
var sha256 = CryptoJS.SHA256("hello").toString();     // 占位，返回空
var sha1 = CryptoJS.SHA1("hello").toString();          // 占位，返回空
var hmac = CryptoJS.HmacSHA256("data", "key").toString(); // 占位，返回空
```

### 6.3 编码器

```javascript
// UTF-8
var wordArray = CryptoJS.enc.Utf8.parse("hello");
var str = CryptoJS.enc.Utf8.stringify(wordArray);

// Base64
var b64WordArray = CryptoJS.enc.Base64.parse("aGVsbG8=");
var b64Str = CryptoJS.enc.Base64.stringify(wordArray);

// Hex
var hexWordArray = CryptoJS.enc.Hex.parse("68656c6c6f");
var hexStr = CryptoJS.enc.Hex.stringify(wordArray);
```

### 6.4 模式和填充

```javascript
CryptoJS.mode.ECB          // ECB 模式
CryptoJS.mode.CBC          // CBC 模式（默认）
CryptoJS.pad.Pkcs7         // PKCS7 填充（默认）
CryptoJS.pad.ZeroPadding   // 零填充
CryptoJS.pad.NoPadding     // 无填充
```

---

## 七、变量系统

### 7.1 @put / @get 规则语法

```
@put:{"token":"tag.span@text","id":"class.uid@attr(data-id)"}
@get:{token}
```

### 7.2 变量查找链（优先级从高到低）

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | 本地变量 | `@put` 存入的变量 |
| 2 | 书源变量 | `source.variable`（持久化） |
| 3 | 书源快捷属性 | `bookSourceUrl` / `bookSourceName` / `bookSourceGroup` |
| 4 | 书籍快捷属性 | `name` / `author` / `bookUrl` / `coverUrl` / `intro` 等 |
| 5 | 章节快捷属性 | `title` / `chapterUrl` / `chapterIndex` / `isVolume` |

### 7.3 JS 中操作变量

```javascript
// 内存缓存（会话内有效）
java.put("key", "value");
var val = java.getStr("key", "默认值");

// 持久化缓存（Rhino: 跨会话; QuickJS: 仅内存）
java.cache.put("token", "abc123");
var token = java.cache.get("token");

// 书源变量（跨请求持久化）
var vars = JSON.parse(source.variable || "{}");
vars.token = "new_token";
java.put("variable", JSON.stringify(vars));
```

### 7.4 {{expression}} 模板变量

```
https://api.com/search?keyword={{key}}&page={{page}}
https://api.com/detail?id={{$.data.id}}
```

解析顺序：变量查找 → 规则执行 → JS执行

### 7.5 jsLib 共享作用域

**纯JS代码** — 执行后结果存为 `_jsLib` 变量

**JSON Map** — 每个 key 对应一个变量：
```json
{
  "util": "https://example.com/util.js",
  "config": "var config = {timeout: 5000};"
}
```

---

## 八、URL 选项

### 8.1 请求选项

```
https://example.com/search,{"method":"POST","body":"key={{key}}"}
```

| 选项 | 说明 |
|------|------|
| `method` | GET / POST（默认GET） |
| `body` | POST请求体 |
| `headers` | 自定义请求头 |
| `charset` | 响应编码，如 `"gbk"` |
| `webView` | 是否使用WebView加载 |
| `retry` | 重试次数 |

### 8.2 发现地址格式

```
推荐::https://example.com/recommend
热门::https://example.com/hot
```

### 8.3 URL 中的 JS

```javascript
@js:
var url = "https://api.com/search";
var body = JSON.stringify({keyword: key, page: page});
url + ",{\"method\":\"POST\",\"body\":\"" + encodeURIComponent(body) + "\"}"
```

---

## 九、规则前缀

| 前缀 | 引擎 | 说明 | 示例 |
|------|------|------|------|
| `@css:` | Rhino | CSS选择器 | `@css:div.book-list > li` |
| `@xpath:` | QuickJS | XPath选择器 | `@xpath://div[@class="book-list"]/ul/li` |
| `@json:` | QuickJS | JSONPath | `@json:$.data.list` |
| `@js:` | 自动 | 执行JS | `@js:result.match(/xxx/)` |
| `@quickjs:` | QuickJS | 强制QuickJS | `@quickjs:const x = 1;` |
| `@rhino:` | Rhino | 强制Rhino | `@rhino:java.get(url)` |
| `@java:` | Rhino | Java互操作 | `@java:java.get(url)` |
| `@ts:` | QuickJS | TypeScript | `@ts:const x: number = 1;` |
| `<js>...</js>` | 自动 | JS标签语法 | `<js>result.match(/xxx/)</js>` |
| `:` | 自动 | JS简写 | `:result.match(/xxx/)` |

### 引擎自动识别

使用 `@js:` 前缀时自动识别：
- 含ES6特征（`const`/`let`/`=>`/`async`/`class`等）→ **QuickJS**
- 含 `java.` 且无ES6特征 → **Rhino**
- 无法确定 → 使用书源 `engine` 字段或默认 **QuickJS**

---

## 十、实战示例

### 10.1 最简单的搜索规则

```javascript
<js>
var list = [];
var items = result.match(/<li[^>]*class="book"[^>]*>[\s\S]*?<\/li>/g) || [];
for (const item of items) {
  list.push({
    name: item.match(/<h3>([^<]*)<\/h3>/)?.[1] || '',
    author: item.match(/作者[：:]\s*([^<]*)/)?.[1] || '',
    bookUrl: item.match(/href="([^"]+)"/)?.[1] || ''
  });
}
JSON.stringify(list);
</js>
```

### 10.2 用 fetch + CryptoJS 解密

```javascript
<js>
var key = CryptoJS.enc.Utf8.parse("1234567890123456");
var iv = CryptoJS.enc.Utf8.parse("1234567890123456");
var encrypted = CryptoJS.AES.encrypt("hello", key, {iv: iv});
var encStr = encrypted.toString();
console.log("加密结果:", encStr);

var decrypted = CryptoJS.AES.decrypt(encStr, key, {iv: iv});
var decStr = CryptoJS.enc.Utf8.stringify(decrypted);
console.log("解密结果:", decStr);
</js>
```

### 10.3 用 jsoup 解析 HTML

```javascript
<js>
var name = java.jsoup.selectFirst(result, "h1.book-name");
var author = java.jsoup.selectFirst(result, "p.author");
var coverUrl = java.jsoup.getAttr(result, "img.cover", "src");
var intro = java.jsoup.selectFirst(result, "div.intro");
JSON.stringify({name, author, coverUrl, intro});
</js>
```

### 10.4 用 fetch + JSON API

```javascript
<js>
var data = JSON.parse(result);
var list = data.data.list.map(item => ({
  name: item.title,
  author: item.author,
  bookUrl: item.url,
  coverUrl: item.cover,
  intro: item.description
}));
JSON.stringify(list);
</js>
```

### 10.5 console.log 调试

```javascript
<js>
console.log("开始解析...");
console.log("result长度:", result.length);
console.log("baseUrl:", baseUrl);
console.log("书名:", book.name);
console.log("作者:", book.author);
console.time("解析耗时");
// ... 解析逻辑 ...
console.timeEnd("解析耗时");
console.log("解析完成！");
result;
</js>
```

### 10.6 纯JS书源函数式写法

```javascript
function search(keyword, page, result) {
  const data = JSON.parse(result);
  return data.list.map(item => ({
    name: item.title,
    author: item.author,
    bookUrl: item.url
  }));
}

function content(result) {
  let text = result.replace(/<script[^>]*>[\s\S]*?<\/script>/g, "");
  text = text.replace(/<[^>]+>/g, "\n").trim();
  return text;
}
```

---

## 十一、常见问题

### Q: fetch() 返回空字符串？
A: 同步模式下 `fetch()` 优先从缓存获取。确保在 `processJsRule`（异步）模式下执行，或使用 `java.ajax()` 并预缓存结果。

### Q: CryptoJS 和 java.aesEncode 有什么区别？
A: `CryptoJS` 是标准 Web API 写法，网页加密代码可直接拷贝。`java.aesEncode` 是阅读3.0兼容写法。两者底层实现相同，推荐用 `CryptoJS`。

### Q: console.log 在哪里看？
A: 在书源调试页面可以看到所有日志输出。

### Q: 为什么有些书源用 `java.` 前缀？
A: 那是阅读3.0的兼容写法。新写的书源推荐直接用标准 JS：`fetch()`、`CryptoJS`、`console.log()`、`btoa()`/`atob()` 等。

### Q: 支持 TypeScript 吗？
A: 支持！使用 `@ts:` 前缀，系统会自动编译为 JS 后由 QuickJS 执行。

### Q: 支持 async/await 吗？
A: 语法支持，但 QuickJS 同步执行模式下异步操作会降级。推荐在异步规则（`processJsRule`）中使用。

### Q: 网页上的 JS 加密代码能直接用吗？
A: 能！`CryptoJS`、`btoa`/`atob`、`JSON`、`Date`、`Math` 等都是全局注入的，直接拷贝粘贴即可。

### Q: QuickJS 和 Rhino 怎么选？
A: 新书源用 QuickJS（ES6+语法+标准Web API），兼容旧书源用 Rhino（java.直接调用）。系统会自动识别，也可以用 `@quickjs:` / `@rhino:` 前缀手动指定。

### Q: QuickJS 同步模式下 java.ajax() 为什么返回空？
A: QuickJS 的 evaluate() 是同步的，无法等待异步的 MethodChannel 返回。解决方案：1. 使用异步规则（`processJsRule`）；2. 预缓存 HTTP 结果（`preCacheHttpResults`）；3. 用 `@rhino:` 前缀走 Rhino 引擎。

### Q: java.cache 在 QuickJS 下能持久化吗？
A: QuickJS 下 `java.cache` 仅在内存中有效（会话内）。如需跨会话持久化，请用 `source.variable` 或走 Rhino 引擎的 `java.cache`（底层是 SharedPreferences）。
