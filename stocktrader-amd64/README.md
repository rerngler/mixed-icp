# IBM Stock Trader Helm Chart

## Introduction

This chart installs the IBM Stock Trader microservices.

## Prerequisites

The user must install and configure the following dependencies:
* IBM Db2 Developer-C
* IBM MQ Advanced for Developers
* IBM Operational Decision Manager
* IBM Event Streams
* Redis

The user must create and configure the following services in the IBM Cloud:
* Watson Tone Analyzer
* API Connect
* Cloud Functions

The [stocktrader project](../README.md) provides instructions for setting up these dependencies.

## Configuration

The following table lists the configurable parameters of this chart and their default values.
The parameters allow you to:
* change the image of any microservice from the one provided by IBM to one that you build (e.g. if you want to try to modify a service)
* enable the deployment of optional microservices (tradr, notification-slack, notification-twitter)

| Parameter                           | Description                                         | Default                                                                         |
| ----------------------------------- | ----------------------------------------------------| --------------------------------------------------------------------------------|
| | | |
| portfolio.image.repository | image repository |  ibmstocktrader/portfolio
| portfolio.image.tag | image tag | latest
| | | |
| stockQuote.image.repository | image repository | ibmstocktrader/stock-quote
| stockQuote.image.tag | image tag | latest
| | | |
| trader.enabled | Deploy trader microservice | true
| trader.image.repository | image repository | ibmstocktrader/trader
| trader.image.tag | image tag | basicregistry
| | | |
| tradr.enabled | Deploy tradr microservice | false
| tradr.image.repository | image repository | ibmstocktrader/tradr
| tradr.image.tag | image tag | latest
| | | |
| messaging.enabled | Deploy messaging microservice | false
| messaging.image.repository | image repository | ibmstocktrader/messaging
| messaging.image.tag | image tag | latest
| | | |
| notificationSlack.enabled | Deploy notification-slack microservice | false
| notificationSlack.image.repository | image repository | ibmstocktrader/notification-slack
| notificationSlack.image.tag | image tag | latest
| | | |
| notificationTwitter.enabled | Deploy notification-twitter microservice | false
| notificationTwitter.image.repository | image repository | ibmstocktrader/notification-twitter
| notificationTwitter.image.tag | image tag | latest

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`.

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart.

## Building and Deploying the Chart

After cloing this repository and changing directory into it, just run `helm package stocktrader` to produce the stocktrader-0.1.2.tgz file.

To load it into ICP, first do a `cloudctl login`, then a `cloudctl catalog load-chart --archive stocktrader-0.1.2.tgz --repo local-charts`.

## Installing the Chart

You can install the chart by setting the current directory to the folder where this chart is located and running the following command:

```console
helm install --tls --name stocktrader --namespace stocktrader . 
```

This sets the Helm release name to `stocktrader` and creates all Kubernetes resources in a namespace called `stocktrader`.

Note you need to make sure that the namespace to which you install it has an image policy allowing it to pull images from
DockerHub (unless you have built the sample yourself and are pulling it from your local Docker image registry).  In the ICP console, choose Manage->Resource Security, then choose Image Policies and create one that allows access to `docker.io/ibmstocktrader/*`.

You can also install this helm chart via the ICP console.  Choose Manage->Helm Repositories, and click "Sync repositories".
Wait a few minutes, then click Catalog in the top right, and scroll down to "stocktrader" (or start typing "stock"
under Search repositories" and it will filter the list down to just charts containing that string).  Then just click
on it and follow the directions, which will show this readme.

## Uninstalling the Chart

```console
$ helm delete --purge stocktrader --tls
```
