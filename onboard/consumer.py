import json
import logging
from typing import Optional

import pika
import yaml


def main_loop(ch, method, properties, body):
    """
    :return:
    """
    try:
        decoded = body.decode('utf8')
        payload = json.loads(decoded)
        print(payload)
        logging.info("Starting vnf on-boarding task for a host {0}".format(payload))
    except Exception as err:
        print(err)


def validate_config(spec, default_mandatory_key=None):
    """Validate config
    :param spec:
    :param default_mandatory_key:
    :return:
    """
    if default_mandatory_key is None:
        default_mandatory_key = [
            "username", "password", "hostname", "queue_name"
        ]

    for k in default_mandatory_key:
        if k not in spec or len(spec[k]) == 0:
            raise ValueError(f"Please create ampq "
                             f"config and define {k}")


def main(config_file: Optional[str] = "config/default.yaml"):
    """
    Read config, create consumer and pass to main_loop
    :param config_file:
    :return:
    """
    with open(config_file, "r") as s:
        config = yaml.safe_load(s)
        if 'ampq' not in config:
            raise ValueError(f"Please create ampq config in {config_file}")

        ampq_config=config['ampq']
        validate_config(ampq_config)

        credentials = pika.PlainCredentials(
            ampq_config['username'],
            ampq_config['password'])

        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=ampq_config['hostname'],
                credentials=credentials)
        )

        logging.getLogger("pika").setLevel(logging.WARNING)
        channel = connection.channel()
        queue_name = ampq_config['queue_name']
        channel.queue_declare(queue=queue_name)
        channel.basic_consume(
            "onboarding",
            main_loop,
            auto_ack=True
        )
        logging.info('Waiting for VNF on boarding request. To stop press CTRL+C')
        try:
            channel.start_consuming()
        except KeyboardInterrupt:
            channel.stop_consuming()
        connection.close()


if __name__ == "__main__":
    """
    Main entry for VNF on boarding listener.
    """
    main()
