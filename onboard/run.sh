# create docker
docker run -d --hostname localhost -p 5672:5672 -p 15672:15672 --name hott-rabbit -e RABBITMQ_DEFAULT_USER=vmware -e RABBITMQ_DEFAULT_PASS=VMware1! rabbitmq:3-management

# publish test event
python publish_test.py