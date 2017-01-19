FROM alpine:latest
# Install cURL
RUN echo -e "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.4/main\n\
https://mirror.tuna.tsinghua.edu.cn/alpine/v3.4/community" > /etc/apk/repositories

RUN apk --update add curl bash openjdk8-jre-base && \
      rm -rf /var/cache/apk/*

# Set environment
ENV JAVA_HOME /usr/lib/jvm/default-jvm
ENV PATH ${PATH}:${JAVA_HOME}/bin

ENV TOMCAT_MAJOR 8
ENV TOMCAT_VERSION 8.5.9


# https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
ENV TOMCAT_TGZ_URL https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz
# not all the mirrors actually carry the .asc files :'(
ENV TOMCAT_ASC_URL https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc


RUN set -x \
        \
        && curl -fSL "$TOMCAT_TGZ_URL" -o tomcat.tar.gz \
        && curl -fSL "$TOMCAT_TGZ_URL.asc" -o tomcat.tar.gz.asc \
        && gpg --batch --verify tomcat.tar.gz.asc tomcat.tar.gz \
        && tar -xvf tomcat.tar.gz --strip-components=1 \
        && rm bin/*.bat \
        && rm tomcat.tar.gz* \
        \
        && nativeBuildDir="$(mktemp -d)" \
        && tar -xvf bin/tomcat-native.tar.gz -C "$nativeBuildDir" --strip-components=1 \
        && nativeBuildDeps=" \
                gcc \
                libapr1-dev \
                libssl-dev \
                make \
                openjdk-${JAVA_VERSION%%[-~bu]*}-jdk=$JAVA_DEBIAN_VERSION \
        " \
        && apt-get update && apt-get install -y --no-install-recommends $nativeBuildDeps && rm -rf /var/lib/apt/lists/* \
        && ( \
                export CATALINA_HOME="$PWD" \
                && cd "$nativeBuildDir/native" \
                && ./configure \
                        --libdir=/usr/lib/jni \
                        --prefix="$CATALINA_HOME" \
                        --with-apr=/usr/bin/apr-1-config \
                        --with-java-home="$(docker-java-home)" \
                        --with-ssl=yes \
                && make -j$(nproc) \
                && make install \
        ) \
        && apt-get purge -y --auto-remove $nativeBuildDeps \
        && rm -rf "$nativeBuildDir" \
        && rm bin/tomcat-native.tar.gz

# verify Tomcat Native is working properly
RUN set -e \
        && nativeLines="$(catalina.sh configtest 2>&1)" \
        && nativeLines="$(echo "$nativeLines" | grep 'Apache Tomcat Native')" \
        && nativeLines="$(echo "$nativeLines" | sort -u)" \
        && if ! echo "$nativeLines" | grep 'INFO: Loaded APR based Apache Tomcat Native library' >&2; then \
                echo >&2 "$nativeLines"; \
                exit 1; \
        fi

EXPOSE 8080
CMD ["catalina.sh", "run"]