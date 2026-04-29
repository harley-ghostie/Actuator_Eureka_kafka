from confluent_kafka import Consumer

conf = {
  "bootstrap.servers": "KAFKA_BOOTSTRAP_SERVER:9092",
  "security.protocol": "SASL_SSL",
  "sasl.mechanisms": "PLAIN",
  "sasl.username": "KAFKA_API_KEY",
  "sasl.password": "KAFKA_API_SECRET",
  "group.id": "pentest-metadata-only",
  "enable.auto.commit": False,
  "session.timeout.ms": 6000,
}
c = Consumer(conf)
md = c.list_topics(timeout=10)
print("Brokers:", [f"{b.host}:{b.port}" for b in md.brokers.values()])
print("Topics:", list(md.topics.keys())[:50])  # só nomes, limitado
c.close()
