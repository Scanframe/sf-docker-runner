# MINIO Server Setup using Docker

## Step 1 : Start minio server with non-persistent data storage policy

Description:

`-p 9000:9000`: Minio server runs on port 9000 inside the docker container, `-e 9000:9000` command is exposing the internal port on external port.  
`-e "MINIO_ACCESS_KEY=access_key"`: It sets an environment variable inside container named as `MINIO_ACCESS_KEY` with the value provided by user. It will be
used when a user wants to access minio server.  
`-e "MINIO_SECRET_KEY=access_key_secret"`: It sets an envrionment variable inside container named as `MINIO_SECRET_KEY` with the value provided by user.    
It will be used when a user wants to access minio server.
`minio/minio`: It is the name of the image.

Once the server has started successfully then MINIO UI can be accessed on this URL: http://127.0.0.1:9000/ .

`sudo docker run -p 9000:9000 -e "MINIO_ACCESS_KEY=access_key" -e "MINIO_SECRET_KEY=access_key_secret"  minio/minio server /data`

To log in the username is the access key and the password is the secret key initially.


## Step 2 : Start the mc container

Description:  
`--net=host`: It enfores the container to use the host networking.
`-it`: run the container in the interactive mode.
`--entrypoint=/bin/sh`: It runs /bin/sh command once the docker container is started
`minio/mc`: It is the name of the image

`sudo docker run --net=host -it --entrypoint=/bin/sh minio/mc`

## Step 3: Connect mc (minio client) to minio server

Description: It adds a new host named as minio that is running on the address [http://127.0.0.1:9000] using
these keys access_key and access_key_secret
`mc config host add minio http://127.0.0.1:9000 access_key access_key_secret`

## Step 4: Create a new bucket

Description: It creates a new bucket named as `newbucket` on minio host.  

```
mc mb minio/newbucket
```

## Step 5: Copy a local file on minio server

Description: It copies a file named as 123.txt to the newly created bucket named as newbucket.  

```
mc cp 123.txt minio/newbucket/123.txt
```


## Step 6: Sync the folder on minio server locally

Description: --newer-than 7:  It filters object(s) newer than 7 days.  

```
mc mirror --newer-than 7 p minio/minioserverbucket
```
