const http = require('http')
const { execFile } = require('child_process')

const PORT = process.env.PORT || 3000

const queue = []
let running = false

function processQueue() {
	if (running || queue.length === 0) return
	running = true
	const { question, sessionId, res } = queue.shift()
	const startedAt = Date.now()

	console.log(
		`[${new Date().toISOString()}] Processing: ${question}${sessionId ? ` (session: ${sessionId})` : ''} (${queue.length} queued)`,
	)

	// The client (e.g. the Slack bridge) may give up on a slow answer; the
	// answer then silently goes nowhere. Log it so lost answers are visible.
	res.on('close', () => {
		if (!res.writableEnded) {
			console.warn(
				`[${new Date().toISOString()}] Client disconnected after ${Math.round((Date.now() - startedAt) / 1000)}s, before the answer could be sent${sessionId ? ` (session: ${sessionId})` : ''}`,
			)
		}
	})

	const args = [question]
	if (sessionId) args.push(sessionId)

	execFile(
		'/ask.sh',
		args,
		// Up to 3 gemini attempts (incl. fresh-session fallback) can take a
		// while; must stay under the Node-RED bridge timeout (600s).
		{ timeout: 540000 },
		(err, stdout, stderr) => {
			running = false
			if (err) {
				console.error(`[${new Date().toISOString()}] Error (code=${err.code}, signal=${err.signal}): ${err.message}`)
				if (stderr) console.error(`[${new Date().toISOString()}] Stderr: ${stderr}`)
				// Never leak raw CLI stderr (color warnings, YOLO banners, tool
				// errors) to the client. Keep diagnostics in the server log above
				// and return a clean, user-facing message instead.
				res.writeHead(500, { 'Content-Type': 'text/plain' })
				res.end('Sorry, I could not answer that right now. Please try again.\n')
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
					`[${new Date().toISOString()}] Done in ${Math.round((Date.now() - startedAt) / 1000)}s.${geminiSessionId ? ` (gemini session: ${geminiSessionId})` : ''}${res.destroyed ? ' Client already gone - answer NOT delivered.' : ''}`,
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
		// Test endpoint: GET /delay/240 responds after 240 s. Lets us check
		// whether slow answers survive the network path (NAT, port proxies)
		// without spending a real Gemini call.
		const delayMatch = req.url.match(/^\/delay\/(\d{1,3})$/)
		if (delayMatch) {
			const seconds = Number(delayMatch[1])
			console.log(`[${new Date().toISOString()}] Delay test started: ${seconds}s`)
			res.on('close', () => {
				if (!res.writableEnded) {
					console.warn(
						`[${new Date().toISOString()}] Delay test: client disconnected before ${seconds}s elapsed`,
					)
				}
			})
			setTimeout(() => {
				res.writeHead(200, { 'Content-Type': 'text/plain' })
				res.end(`ok after ${seconds}s\n`)
				console.log(
					`[${new Date().toISOString()}] Delay test finished: ${seconds}s${res.destroyed ? ' - client already gone' : ''}`,
				)
			}, seconds * 1000)
			return
		}

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

// While an answer is being computed the connection is silent for minutes;
// NAT tables and port proxies on the way may drop such idle connections.
// TCP keep-alive probes every 30 s keep the path open.
server.on('connection', (socket) => {
	socket.setKeepAlive(true, 30000)
})

server.listen(PORT, () => {
	console.log(
		`[${new Date().toISOString()}] HTTP server listening on port ${PORT}`,
	)
})
