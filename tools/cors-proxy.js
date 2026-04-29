const http = require('http');
const https = require('https');
const url = require('url');

const PORT = 8888;

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Target-Url');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  let body = [];
  req.on('data', chunk => {
    body.push(chunk);
  });

  req.on('end', () => {
    body = Buffer.concat(body);
    
    // 从 URL 路径获取目标 URL
    let targetUrl = req.url.substring(1);
    
    // 或者从请求头获取
    const headerTargetUrl = req.headers['x-target-url'];
    if (headerTargetUrl && headerTargetUrl !== 'undefined') {
      targetUrl = headerTargetUrl;
    }
    
    if (!targetUrl || targetUrl === 'favicon.ico' || targetUrl === '') {
      res.writeHead(400);
      res.end('Missing target URL');
      return;
    }

    console.log(`[Proxy] ${req.method} ${targetUrl}`);

    try {
      const parsedUrl = new URL(targetUrl);
      
      const options = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || (parsedUrl.protocol === 'https:' ? 443 : 80),
        path: parsedUrl.pathname + parsedUrl.search,
        method: req.method,
        headers: {}
      };

      // 复制请求头，排除一些特定的头
      for (const [key, value] of Object.entries(req.headers)) {
        if (key.toLowerCase() !== 'host' && 
            key.toLowerCase() !== 'x-target-url' &&
            key.toLowerCase() !== 'origin' &&
            key.toLowerCase() !== 'referer') {
          options.headers[key] = value;
        }
      }
      
      options.headers['host'] = parsedUrl.host;

      const protocol = parsedUrl.protocol === 'https:' ? https : http;
      
      const proxyReq = protocol.request(options, (proxyRes) => {
        // 复制响应头
        const headersToSkip = ['transfer-encoding', 'connection'];
        for (const [key, value] of Object.entries(proxyRes.headers)) {
          if (!headersToSkip.includes(key.toLowerCase())) {
            res.setHeader(key, value);
          }
        }
        
        res.writeHead(proxyRes.statusCode);
        proxyRes.pipe(res);
      });

      proxyReq.on('error', (e) => {
        console.error(`Proxy error: ${e.message}`);
        res.writeHead(502);
        res.end(`Proxy error: ${e.message}`);
      });

      if (body.length > 0) {
        proxyReq.write(body);
      }
      proxyReq.end();
      
    } catch (e) {
      console.error(`URL parse error: ${e.message}`);
      res.writeHead(400);
      res.end(`Invalid URL: ${e.message}`);
    }
  });
});

server.listen(PORT, () => {
  console.log(`\n🚀 CORS Proxy Server running at http://localhost:${PORT}`);
  console.log(`📡 Usage: http://localhost:${PORT}/https://example.com/api`);
  console.log(`   Or use header: X-Target-Url: https://example.com/api\n`);
});
