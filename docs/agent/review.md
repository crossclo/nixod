# review: review and approve a join request

Mode: the user asks to review a join request (a pull request, or a
`join/<name>` branch), on a machine already in the network.

1. **Review:** `nixod review <pr number>` (in the repo). It changes nothing in
   the working tree. It shows the machines added or removed, the `network.nix`
   diff and the files touched, then builds the new host and the hub.
2. **Explain it to the user** in plain words: which machine, which folders it
   gets, anything unusual. Read the output yourself; don't only relay it.
   - **"this request also changes shared files"**: the request touches what
     other machines run. Show the user that diff and explain it. A join
     request has no reason to do this: suggest asking the new machine to drop
     those changes. Never approve it without the user understanding it.
   - A machine **removed** by a join request: stop and ask.
   - A build failure: don't approve; tell the new machine's side what failed.
3. **Approve only on the user's explicit yes:** `nixod approve <pr number>`.
   It refuses if the request changed since the review (review again then). It
   merges with a commit signed by this machine and pushes; GitHub marks the
   pull request merged.
4. **Then:** the hub applies it within minutes (`ssh root@<hub> nixod status`).
   The other hosts get a notification at their next check.
