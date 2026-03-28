# RPC Reference

This page is generated from the method registry in `src/gateway/registry.zig`.
Regenerate with:

```powershell
./scripts/generate-rpc-reference.ps1
```

Source of truth: [`src/gateway/registry.zig`](https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/blob/main/src/gateway/registry.zig)

## Common Envelope

```json
{
  "id": "req-1",
  "method": "health",
  "params": {}
}
```

## Summary

- Total methods: **203**
- Prefix groups: **37**

## Prefix Overview

| Prefix | Count |
| --- | ---: |
| (root) | 15 |
| acp | 11 |
| agent | 2 |
| agents | 7 |
| auth | 6 |
| browser | 2 |
| canvas | 1 |
| channels | 4 |
| chat | 4 |
| config | 6 |
| cron | 7 |
| device | 6 |
| doctor | 1 |
| edge | 25 |
| exec | 8 |
| file | 4 |
| gateway | 1 |
| logs | 1 |
| models | 1 |
| node | 16 |
| process | 6 |
| push | 1 |
| secrets | 7 |
| security | 1 |
| session | 1 |
| sessions | 13 |
| skills | 4 |
| system | 12 |
| talk | 2 |
| tasks | 4 |
| tools | 1 |
| tts | 6 |
| update | 3 |
| usage | 2 |
| voicewake | 2 |
| web | 6 |
| wizard | 4 |

## Method Index

### (root)

- agent
- connect
- delegate_task
- doctor
- execute_code
- health
- last-heartbeat
- poll
- send
- set-heartbeats
- shutdown
- status
- system-event
- system-presence
- wake

### acp

- acp.describe
- acp.prompt
- acp.sessions.cancel
- acp.sessions.events
- acp.sessions.fork
- acp.sessions.get
- acp.sessions.list
- acp.sessions.load
- acp.sessions.messages
- acp.sessions.new
- acp.sessions.resume

### agent

- agent.identity.get
- agent.wait

### agents

- agents.create
- agents.delete
- agents.files.get
- agents.files.list
- agents.files.set
- agents.list
- agents.update

### auth

- auth.oauth.complete
- auth.oauth.import
- auth.oauth.logout
- auth.oauth.providers
- auth.oauth.start
- auth.oauth.wait

### browser

- browser.open
- browser.request

### canvas

- canvas.present

### channels

- channels.logout
- channels.status
- channels.telegram.bot.send
- channels.telegram.webhook.receive

### chat

- chat.abort
- chat.history
- chat.inject
- chat.send

### config

- config.apply
- config.get
- config.patch
- config.schema
- config.schema.lookup
- config.set

### cron

- cron.add
- cron.list
- cron.remove
- cron.run
- cron.runs
- cron.status
- cron.update

### device

- device.pair.approve
- device.pair.list
- device.pair.reject
- device.pair.remove
- device.token.revoke
- device.token.rotate

### doctor

- doctor.memory.status

### edge

- edge.acceleration.status
- edge.alignment.evaluate
- edge.collaboration.plan
- edge.enclave.prove
- edge.enclave.status
- edge.finetune.cancel
- edge.finetune.cluster.plan
- edge.finetune.job.get
- edge.finetune.run
- edge.finetune.status
- edge.handoff.plan
- edge.homomorphic.compute
- edge.identity.trust.status
- edge.marketplace.revenue.preview
- edge.mesh.status
- edge.multimodal.inspect
- edge.personality.profile
- edge.quantum.status
- edge.router.plan
- edge.swarm.plan
- edge.voice.transcribe
- edge.wasm.execute
- edge.wasm.install
- edge.wasm.marketplace.list
- edge.wasm.remove

### exec

- exec.approval.request
- exec.approval.resolve
- exec.approval.waitdecision
- exec.approvals.get
- exec.approvals.node.get
- exec.approvals.node.set
- exec.approvals.set
- exec.run

### file

- file.patch
- file.read
- file.search
- file.write

### gateway

- gateway.identity.get

### logs

- logs.tail

### models

- models.list

### node

- node.canvas.capability.refresh
- node.describe
- node.event
- node.invoke
- node.invoke.result
- node.list
- node.pair.approve
- node.pair.list
- node.pair.reject
- node.pair.request
- node.pair.verify
- node.pending.ack
- node.pending.drain
- node.pending.enqueue
- node.pending.pull
- node.rename

### process

- process.kill
- process.list
- process.poll
- process.read
- process.start
- process.wait

### push

- push.test

### secrets

- secrets.reload
- secrets.resolve
- secrets.store.delete
- secrets.store.get
- secrets.store.list
- secrets.store.set
- secrets.store.status

### security

- security.audit

### session

- session.status

### sessions

- sessions.compact
- sessions.delete
- sessions.history
- sessions.list
- sessions.patch
- sessions.preview
- sessions.reset
- sessions.resolve
- sessions.search
- sessions.send
- sessions.usage
- sessions.usage.logs
- sessions.usage.timeseries

### skills

- skills.bins
- skills.install
- skills.status
- skills.update

### system

- system.boot.attest
- system.boot.attest.verify
- system.boot.policy.get
- system.boot.policy.set
- system.boot.status
- system.boot.verify
- system.maintenance.plan
- system.maintenance.run
- system.maintenance.status
- system.rollback.cancel
- system.rollback.plan
- system.rollback.run

### talk

- talk.config
- talk.mode

### tasks

- tasks.events
- tasks.get
- tasks.list
- tasks.search

### tools

- tools.catalog

### tts

- tts.convert
- tts.disable
- tts.enable
- tts.providers
- tts.setProvider
- tts.status

### update

- update.plan
- update.run
- update.status

### usage

- usage.cost
- usage.status

### voicewake

- voicewake.get
- voicewake.set

### web

- web.extract
- web.login.complete
- web.login.start
- web.login.status
- web.login.wait
- web.search

### wizard

- wizard.cancel
- wizard.next
- wizard.start
- wizard.status

