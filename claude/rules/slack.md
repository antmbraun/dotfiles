# Slack follow-up reviews

When reviewing my Slack for asks I haven't answered, a message counts as answered if I reacted to it
with an emoji or replied in its thread. Before reporting anything as "no reply":

- Read it with `response_format: detailed` — concise mode hides reactions and the "Thread: N replies"
  count.
- Open any thread it has and look for my reply there.
- Don't conclude "no reply" from my message being absent in a `from:` search: its pagination can
  report "End of results" early and skip whole time windows.
