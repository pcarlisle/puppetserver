FROM clojure:lein
WORKDIR /usr/src/app
COPY . /usr/src/app/
ENV EZBAKE_NODEPLOY=1
ENV EZBAKE_ALLOW_UNREPRODUCIBLE_BUILDS=1
ENV MOCK=''
ENV COW=base-stretch-i386.cow
RUN apt-get update && \
    apt-get install -y make ruby ruby-dev build-essential && \
    git config --global user.email "root@localhost" && \
    git config --global user.name "Docker Puppet Builder" && \
    gem install fpm && \
    lein with-profile ezbake ezbake local-build

FROM openjdk:8-slim
COPY --from=0 /usr/src/app/output /packages

ENV DUMB_INIT_VERSION="1.2.1"
ENV PATH=/opt/puppetlabs/server/bin:/opt/puppetlabs/puppet/bin:/opt/puppetlabs/bin:$PATH

RUN apt-get update && \
    apt-get install -y wget && \
    wget http://apt.puppetlabs.com/puppet6-nightly/puppet6-nightly-release-stretch.deb && \
    wget https://github.com/Yelp/dumb-init/releases/download/v"$DUMB_INIT_VERSION"/dumb-init_"$DUMB_INIT_VERSION"_amd64.deb && \
    dpkg -i puppet6-nightly-release-stretch.deb && \
    dpkg -i dumb-init_"$DUMB_INIT_VERSION"_amd64.deb && \
    apt-get update && \
    apt install -y /packages/deb/stretch/puppet6/puppet*

# COPY puppetserver /etc/default/puppetserver
# COPY logback.xml /etc/puppetlabs/puppetserver/
# COPY request-logging.xml /etc/puppetlabs/puppetserver/

RUN puppet config set autosign true --section master
RUN chown -R puppet:puppet /etc/puppetlabs/puppet/ssl
RUN chown -R puppet:puppet /opt/puppetlabs/server/data/puppetserver/

EXPOSE 8140

ENTRYPOINT ["dumb-init","/opt/puppetlabs/bin/puppetserver"]
CMD ["foreground" ]
