import argparse
import json
import logging
import pika
import yaml
import argparse

data_payload = '''
{
    "command": "test12",
    "data": {
        "servers": [
            {
                "idrac_ip": "172.25.166.147",
                "idrac_user": "vmware",
                "idrac_password": "zyBOqZLr8TTc0q",
                "esxi_ip": "172.25.166.146",
                "esxi_netmask": "255.255.255.240",
                "esxi_gateway": "172.25.166.145",
                "vcsa_ip": "vcsa.ztp.vmw.run",
                "vcsa_user": "administrator@vsphere.local",
                "vcsa_password": "VMware1!",
                "vcsa_datacenter": "Datacenter",
                "vcsa_cluster": "ZTP",
                "vcsa_vds": "vds-ztp"
            }
        ],
        "nodepool": {
            "tca_ip": "tca.ztp.vmw.run",
            "tca_user": "administrator@vsphere.local",
            "tca_password": "VMware1!",
            "vimName": "ZTP",
            "tkgMgmtCluster": "tkg-m",
            "tkgWrkldCluster": "tkg-w",
            "tkgDatacenter": "Datacenter",
            "tkgDatastore": "das-146",
            "tkgFolder": "tkg-ztp-test",
            "tkgCluster": "ZTP",
            "tkgTemplate": "tkg/photon-3-kube-v1.21.14-vmware.2-tkg.4-fd7fe2-21063162",
            "tkgNetwork": "vds-ztp/vds-ztp-native",
            "tcaBomReleaseRef": "tbr-bom-2.2.0-v1.21.14---vmware.2-tkg.5-tca.21066684"
        }
    }
}
'''


def main(json_pd):
    """
    :param json_pd:
    :return:
    """
    with open("config/default.yaml", "r") as s:
        try:
            default_config = yaml.safe_load(s)
            credentials = pika.PlainCredentials(
                default_config['ampq']['username'],
                default_config['ampq']['password']
            )

            connection = pika.BlockingConnection(
                pika.ConnectionParameters(
                    host=default_config['ampq']['hostname'],
                    credentials=credentials)
            )

            channel = connection.channel()
            channel.queue_declare(
                queue=default_config['ampq']['queue_name']
            )
            channel.basic_publish(
                exchange='',
                routing_key='onboarding',
                body=json_pd)
            connection.close()
            logging.info("Pushed job to a queue")
        except yaml.YAMLError as exc:
            print(exc)


if __name__ == "__main__":
    """
    Main entry to push event
    """
    # # parser = argparse.ArgumentParser()
    # # parser.add_argument(
    # #     '-hh', '--hostname',
    # #     help='Hostname of esxi',
    # #     required=True)
    # args = vars(parser.parse_args())
    # pd = json.dumps(data_payload)
    main(data_payload)
