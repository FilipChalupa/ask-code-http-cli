const http = require("http");
const { execFile } = require("child_process");

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405, { "Content-Type": "text/plain" });
    res.end("POST a question in the request body\n");
    return;
  }

  let body = "";
  req.on("data", (chunk) => (body += chunk));
  req.on("end", () => {
    const question = body.trim();
    if (!question) {
      res.writeHead(400, { "Content-Type": "text/plain" });
      res.end("Empty question\n");
      return;
    }

    console.log(`[${new Date().toISOString()}] Question: ${question}`);

    execFile("/ask.sh", [question], { timeout: 300000 }, (err, stdout, stderr) => {
      if (err) {
        console.error(`[${new Date().toISOString()}] Error: ${err.message}`);
        res.writeHead(500, { "Content-Type": "text/plain" });
        res.end(stderr || err.message);
        return;
      }
      console.log(`[${new Date().toISOString()}] Done.`);
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(stdout);
    });
  });
});

server.listen(PORT, () => {
  console.log(`[${new Date().toISOString()}] HTTP server listening on port ${PORT}`);
});
