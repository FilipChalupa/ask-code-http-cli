const http = require('http')
const { execFile } = require('child_process')

const PORT = process.env.PORT || 3000

const queue = []
let running = false

function processQueue() {
	if (running || queue.length === 0) return
	running = true
	const { question, sessionId, res } = queue.shift()

	console.log(
		`[${new Date().toISOString()}] Processing: ${question}${sessionId ? ` (session: ${sessionId})` : ''} (${queue.length} queued)`,
	)

	const args = [question]
	if (sessionId) args.push(sessionId)

	execFile(
		'/ask.sh',
		args,
		{ timeout: 300000 },
		(err, stdout, stderr) => {
			running = false
			if (err) {
				console.error(`[${new Date().toISOString()}] Error (code=${err.code}, signal=${err.signal}): ${err.message}`)
				if (stderr) console.error(`[${new Date().toISOString()}] Stderr: ${stderr}`)
				res.writeHead(500, { 'Content-Type': 'text/plain' })
				res.end(stderr || err.message)
			} else {
				// Split off SESSION_ID: line from the end of stdout
				const lines = stdout.trimEnd().split('\n')
				let geminiSessionId = null
				if (
					lines.length > 0 &&
					lines[lines.length - 1].startsWith('SESSION_ID:')
				) {
					geminiSessionId = lines.pop().replace('SESSION_ID:', '')
				}
				const answer = lines.join('\n')

				console.log(
					`[${new Date().toISOString()}] Done.${geminiSessionId ? ` (gemini session: ${geminiSessionId})` : ''}`,
				)

				const headers = { 'Content-Type': 'text/plain' }
				if (sessionId) {
					headers['X-Session-Id'] = sessionId
				}
				res.writeHead(200, headers)
				res.end(answer + '\n')
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

	const sessionId = req.headers['x-session-id'] || null

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
			`[${new Date().toISOString()}] Queued: ${question}${sessionId ? ` (session: ${sessionId})` : ''} (${queue.length + 1} total)`,
		)
		queue.push({ question, sessionId, res })
		processQueue()
	})
})

server.listen(PORT, () => {
	console.log(
		`[${new Date().toISOString()}] HTTP server listening on port ${PORT}`,
	)
})
