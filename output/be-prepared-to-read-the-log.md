# Be Prepared to Read the Log

I used to find out that a row had changed by asking the table again. A job woke up, looked at `updated_at`, and hoped the window still meant what I thought it meant. When the job died halfway, I ran it again. Sometimes the row had moved on. Sometimes it had not. The table would not tell me which.

PostgreSQL had already written the change down. Every commit lands in the write-ahead log before anyone is allowed to believe it. I was polling a result and ignoring the record of how that result got there.

That record is enough. Change data capture is just reading it.

## The write is the message

In this proof of concept, Debezium Server sits next to PostgreSQL and reads that log with `pgoutput`. It does not query the tables on a timer. An insert, an update, a delete, and the first snapshot each become a message.

The database is the inventory schema from Debezium’s own example: `customers`, `orders`, `products`, `products_on_hand`, and `geom`. Each table gets its own Pub/Sub topic, named `db-inventory.inventory.<table>`. One stream in, five topics out. Subscribers choose the table they care about and leave the others alone.

A message is small. The useful part is `op`, `before`, and `after`. `op` is `r` when the row comes from the first snapshot, `c` when someone inserts it later, `u` on an update, `d` on a delete. `after` is the row as it is now. `before` is the row as it was, which is what you still have when the row is gone.

I can see this without a cloud account. Compose brings up PostgreSQL, Debezium, and a Pub/Sub emulator. I insert Ada Lovelace. I pull the `customers` subscription. The message says `op` is `c`, and `after` has her name and email. The same insert done by hand in Adminer shows up the same way. The log does not care which client held the pen.

## Same topic, two answers

A real project is the same pipe with the emulator taken out. Debezium publishes to Pub/Sub in Google Cloud. The `customers` topic has two subscriptions, because the two things I want are different.

One subscription writes the raw message to BigQuery and stops. That table is a changelog. A snapshot row, an insert, a second delivery of the same insert: each one stays. I can ask what Debezium sent, in the order it was stored. I cannot ask that table who the customer is right now without more work.

The other subscription pushes the message to a Cloud Function. The function keeps a second table with the same columns as `inventory.customers`: one row per customer. An insert, a snapshot, or an update runs a `MERGE` on `id`. A delete removes that `id`. The function also writes one log line, `op=c id=1005 Ada Lovelace ada@example.com`, so I can see the change without opening a query.

If the function fails, the changelog still has the message. The current table stays as it was. Pub/Sub delivers again. That is the deal I already accepted when I chose a log.

## A second time should be boring

Pub/Sub will hand you the same message twice. It will also, in this setup, not promise order: the sink has ordering turned off. So the function does not try to remember every message id. It applies the row.

Apply the same customer twice and the `MERGE` sets the same name and the same email. Apply a delete twice and the second delete finds nothing to remove. That is the property I want. The operation can run again without making a second customer.

There is a limit, and it is a real one. The function does not compare log positions. An older update that arrives late can overwrite a newer one. I would not use this table as the system of record until a stale event loses to a fresher one. For the proof of concept I left the hole visible. The changelog next to it still has both messages, so I can see the lie the current table told.

The expensive part was never the extra `MERGE`. The expensive part is a consumer that increments, appends, or sends mail, and then does it again because the message came twice. Those need a record of what already happened. Keeping the current row is the cheap case. I took the cheap case on purpose.

## What I stopped doing

The table in PostgreSQL remains the place where the write is true. BigQuery is a copy. The function is a copy with a shorter memory. Both are downstream of a log PostgreSQL was already keeping.

I no longer wake a job up to ask what changed. I let the commit emit the change, and I write the consumer so that a repeat is dull. The snapshot is just the first repeat: every row that already existed, delivered once, applied the same way as a later insert.

Be prepared to read the log. Then be prepared to apply it twice.
