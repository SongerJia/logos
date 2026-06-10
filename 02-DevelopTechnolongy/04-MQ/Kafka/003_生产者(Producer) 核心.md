|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|3.1|发送消息完整流程|1) 拦截器 → 2) 序列化 → 3) Partition 选择器 → 4) 追加到 RecordAccumulator（批次缓存）→ 5) Sender 线程批量发往 Broker；画时序图|🔥🔥🔥|
|3.2|Partition 选择策略|指定 Partition（直接发）/ 有 Key（hash(key) % numPartitions，保证相同Key有序）/ 无 Key（轮询 sticky partition，Kafka 2.4+ 优化）|🔥🔥🔥 **高频**|
|3.3|ACK 机制|acks=0（不等待，最快最不可靠）/ acks=1（Leader写入即ACK）/ acks=all（所有ISR副本写入，最慢最可靠）；与吞吐量/可靠性的权衡|🔥🔥🔥|
|3.4|重试机制与幂等性|retries 参数（默认 Integer.MAX_VALUE）/ 重试间隔(retry.backoff.ms)；幂等 Producer（enable.idempotence=true，PID+序列号去重，0.11+ 引入）|🔥🔥🔥|
|3.5|批量发送与压缩|batch.size（16KB默认）/ linger.ms（延迟换吞吐）/ compression.type（none/gzip/snappy/lz4/zstd）；压缩对吞吐和CPU的权衡|核|
|3.6|RecordAccumulator 缓冲区|每个 Partition 一个 Deque；满了会阻塞（max.block.ms 超时抛异常）；缓冲区大小(buffer.memory=32MB默认)调优|热|