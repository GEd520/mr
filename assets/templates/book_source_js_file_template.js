/**
 * 纯JS书源模板
 *
 * 这是全新的书源格式，整个书源就是一个JS文件。
 * 通过导出对象定义书源的所有信息和规则。
 *
 * 可用内置变量：
 *   result  - 当前请求的响应内容
 *   baseUrl - 当前页面的基础URL
 *   source  - 书源元数据对象
 *   book    - 当前书籍信息
 *   chapter - 当前章节信息
 *   cookie  - Cookie信息
 *
 * 可用桥接方法：
 *   java.get(url, headers)         - HTTP GET
 *   java.post(url, body, headers)  - HTTP POST
 *   java.ajax(url, headers)        - 同java.get
 *   java.put(key, value)           - 存储变量
 *   java.getStr(key, defaultValue) - 读取变量
 *   java.jsoup.select(html, css)   - CSS选择器
 *   java.jsoup.selectFirst(html, css) - CSS选择首个
 *   java.jsoup.getAttr(html, css, attr) - 获取属性
 *   java.regex.match(str, pattern) - 正则匹配
 *   java.regex.matchAll(str, pattern) - 正则匹配全部
 *   java.aesEncode/Decode(data, key, iv) - AES加解密
 *   java.md5Encode(str)            - MD5哈希
 *   java.base64Encode/Decode(str)  - Base64编解码
 *   java.cache.get/put/delete(key) - 持久化缓存
 *   java.log(msg)                  - 日志输出
 *   CryptoJS                       - 加密库（AES/MD5/SHA等）
 */

const source = {
  // ===== 基本信息 =====
  bookSourceUrl: "",
  bookSourceName: "",
  bookSourceGroup: "JS书源",
  bookSourceType: 0,  // 0文字 1音频 2图片 3文件 4视频
  enabled: true,
  enabledExplore: true,
  enabledCookieJar: true,
  engine: "quickjs",

  // ===== 网络配置 =====
  header: JSON.stringify({
    "User-Agent": "Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
  }),

  // ===== 搜索 =====
  searchUrl: "https://js.example.com/search?key={{key}}&page={{page}}",

  // ===== 发现 =====
  exploreUrl: "推荐::https://js.example.com/recommend\n热门::https://js.example.com/hot\n更新::https://js.example.com/update",

  // ===== 搜索规则 =====
  search(keyword, page, result) {
    // result 是搜索页面的HTML/JSON内容
    // 返回书籍列表数组
    const list = [];
    // TODO: 解析result，提取书籍信息
    // 示例：使用jsoup解析HTML
    // const items = java.jsoup.select(result, "div.book-list > li");
    // for (const item of items) {
    //   list.push({
    //     name: java.jsoup.selectFirst(item, "h3 a").trim(),
    //     author: java.jsoup.selectFirst(item, "p.author").replace("作者：", "").trim(),
    //     bookUrl: java.jsoup.getAttr(item, "h3 a", "href"),
    //     coverUrl: java.jsoup.getAttr(item, "img", "src"),
    //     intro: java.jsoup.selectFirst(item, "p.intro").trim(),
    //     kind: java.jsoup.selectFirst(item, "span.category").trim(),
    //     lastChapter: java.jsoup.selectFirst(item, "a.chapter").trim(),
    //   });
    // }
    return list;
  },

  // ===== 发现规则 =====
  explore(url, result) {
    // result 是发现页面的内容
    // 返回书籍列表数组，格式同search
    return this.search("", 1, result);
  },

  // ===== 详情规则 =====
  bookInfo(result) {
    // result 是书籍详情页的内容
    // 返回书籍详细信息对象
    const info = {};
    // TODO: 解析result，提取书籍详情
    // 示例：
    // info.name = java.jsoup.selectFirst(result, "h1.book-name").trim();
    // info.author = java.jsoup.selectFirst(result, "p.author").replace("作者：", "").trim();
    // info.intro = java.jsoup.selectFirst(result, "div.intro").trim();
    // info.coverUrl = java.jsoup.getAttr(result, "img.cover", "src");
    // info.tocUrl = java.jsoup.getAttr(result, "a.read-btn", "href");
    // info.kind = java.jsoup.selectFirst(result, "span.category").trim();
    // info.lastChapter = java.jsoup.selectFirst(result, "span.last-chapter").trim();
    // info.wordCount = java.jsoup.selectFirst(result, "span.word-count").trim();
    return info;
  },

  // ===== 目录规则 =====
  toc(result) {
    // result 是目录页的内容
    // 返回章节列表数组
    const chapters = [];
    // TODO: 解析result，提取章节列表
    // 示例：
    // const items = java.jsoup.select(result, "div.chapter-list li");
    // for (const item of items) {
    //   chapters.push({
    //     name: java.jsoup.selectFirst(item, "a").trim(),
    //     url: java.jsoup.getAttr(item, "a", "href"),
    //     isVolume: item.includes("volume") ? true : false,
    //   });
    // }
    return chapters;
  },

  // ===== 正文规则 =====
  content(result) {
    // result 是正文页的内容
    // 返回正文文本
    // TODO: 解析result，提取正文
    // 示例：
    // let text = java.jsoup.selectFirst(result, "div.content");
    // text = text.replace(/<script[^>]*>[\s\S]*?<\/script>/g, "");
    // text = text.replace(/<[^>]+>/g, "\n").trim();
    // return text;
    return "";
  },

  // ===== 下一页目录URL（可选）=====
  nextTocUrl(result) {
    // 如果目录有多页，返回下一页URL，否则返回空
    // const next = java.jsoup.getAttr(result, "a.next-page", "href");
    // return next || "";
    return "";
  },

  // ===== 下一页正文URL（可选）=====
  nextContentUrl(result) {
    // 如果正文有多页，返回下一页URL，否则返回空
    // const next = java.jsoup.getAttr(result, "a.next-page", "href");
    // return next || "";
    return "";
  },
};
