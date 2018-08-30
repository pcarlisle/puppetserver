FROM clojure:lein-alpine
WORKDIR /usr/src/app

RUN apk add --no-cache make && \
    apk add --no-cache java-jffi-native libc6-compat shadow

COPY project.clj /usr/src/app/

RUN lein deps


COPY . /usr/src/app

RUN lein gem install --install-dir /opt/puppetlabs/server/data/puppetserver/vendored-jruby-gems \
    --no-ri --no-rdoc $(cat resources/ext/build-scripts/jruby-gem-list.txt | sed 's/ /:/')

RUN lein uberjar


FROM openjdk:8-jre-alpine

COPY docker/conf.d /etc/puppetlabs/puppetserver/conf.d
COPY ezbake/config/services.d /etc/puppetlabs/puppetserver/services.d
COPY ezbake/system-config/services.d/bootstrap.cfg /etc/puppetlabs/puppetserver/bootstrap.cfg
COPY docker/puppetserver-standalone/logback.xml /etc/puppetlabs/puppetserver/
COPY docker/puppetserver-standalone/request-logging.xml /etc/puppetlabs/puppetserver/

RUN mkdir -p /var/run/puppetlabs/puppetserver /var/log/puppetlabs/puppetserver

COPY --from=0 /opt/puppetlabs/server/data/puppetserver/vendored-jruby-gems /opt/puppetlabs/server/data/puppetserver/vendored-jruby-gems
COPY --from=0 /usr/src/app/target/puppet-server-release.jar /

COPY ruby/puppet/lib /puppet/lib
COPY ruby/facter/lib /facter/lib
COPY ruby/hiera/lib /hiera/lib

RUN apk add --no-cache java-jffi-native libc6-compat shadow

EXPOSE 8140

CMD java -cp /puppet-server-release.jar clojure.main -m puppetlabs.trapperkeeper.main -b /etc/puppetlabs/puppetserver/bootstrap.cfg,/etc/puppetlabs/puppetserver/services.d -c /etc/puppetlabs/puppetserver/conf.d
