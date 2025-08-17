const express = require('express');
const path = require('path');
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));
app.get('/health', (_, res) => res.json({ ok: true }));
const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`Claim web listening on :${port}`));
