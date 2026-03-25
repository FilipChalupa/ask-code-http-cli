const http = require('http')
const { execFile } = require('child_process')

const PORT = process.env.PORT || 3000

const queue = []
let running = false

function processQueue() {
	if (running || queue.length === 0) return
	running = true
	const { question, res } = queue.shift()

	console.log(
		`[${new Date().toISOString()}] Processing: ${question} (${queue.length} queued)`,
	)

	execFile(
		'/ask.sh',
		[question],
		{ timeout: 300000 },
		(err, stdout, stderr) => {
			running = false
			if (err) {
				console.error(`[${new Date().toISOString()}] Error: ${err.message}`)
				res.writeHead(500, { 'Content-Type': 'text/plain' })
				res.end(stderr || err.message)
			} else {
				console.log(`[${new Date().toISOString()}] Done.`)
				res.writeHead(200, { 'Content-Type': 'text/plain' })
				res.end(stdout)
			}
			processQueue()
		},
	)
}

const server = http.createServer((req, res) => {
	if (req.method === 'GET') {
		res.writeHead(200, { 'Content-Type': 'text/plain' })
		res.end(`ok\nqueued: ${queue.length}\nbusy: ${running}\n`)
		return
	}

	if (req.method !== 'POST') {
		res.writeHead(405, { 'Content-Type': 'text/plain' })
		res.end('POST a question in the request body\n')
		return
	}

	let body = ''
	req.on('data', (chunk) => (body += chunk))
	req.on('end', () => {
		const question = body.trim()
		if (!question) {
			res.writeHead(400, { 'Content-Type': 'text/plain' })
			res.end('Empty question\n')
			return
		}

		console.log(
			`[${new Date().toISOString()}] Queued: ${question} (${queue.length + 1} total)`,
		)
		queue.push({ question, res })
		processQueue()
	})
})

server.listen(PORT, () => {
	console.log(
		`[${new Date().toISOString()}] HTTP server listening on port ${PORT}`,
	)
})
