FROM ubuntu:18.04 as build

LABEL maintainer="Abdul Alfozan https://github.com/alfozan"
LABEL description="Build Spark 2.3 distribution with Hadoop 2.8 and S3 support"

RUN apt-get update && apt-get install -y locales && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8

# Python pip
RUN apt-get install -y git python-pip

# Oracle Java 8 (JDK)
RUN apt-get install -y software-properties-common \
  && echo y | add-apt-repository ppa:webupd8team/java \
  && apt-get update \
  && echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections \
  && apt-get install -y oracle-java8-installer
ENV JAVA_HOME=/usr/lib/jvm/java-8-oracle

# clone Spark 2.3 source
ARG SPARK_VERSION=2.3.0
ARG HADOOP_VERSION=2.8.3
ARG SPARK_PACKAGE=spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}
ENV SPARK_HOME="/spark"
RUN git clone --branch "v${SPARK_VERSION}" --single-branch --depth=1 https://github.com/apache/spark.git ${SPARK_HOME}

# Install R packages for sparkr support
RUN DEBIAN_FRONTEND=noninteractive apt-get install tzdata -y
RUN apt-get install r-base -y
RUN apt-get install texlive-latex-base texlive-fonts-recommended -y
RUN R -e "install.packages(c('knitr', 'rmarkdown', 'testthat', 'e1071', 'survival'), repos='http://cran.us.r-project.org')"
WORKDIR ${SPARK_HOME}/R
RUN ./install-dev.sh

# Build Spark
WORKDIR ${SPARK_HOME}
ARG MAVEN_OPTS="-Xmx2g -XX:ReservedCodeCacheSize=512m"
RUN ./dev/make-distribution.sh --name "hadoop${HADOOP_VERSION}" --tgz --pip --r -Psparkr -Phive -Phive-thriftserver -Phadoop-2.7 -Dhadoop.version=${HADOOP_VERSION}

# repackage tgz file
RUN tar -xzf "${SPARK_PACKAGE}.tgz"
# Download extra jars and
RUN  wget -P ${SPARK_PACKAGE}/jars/ http://central.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar \
  && wget -P ${SPARK_PACKAGE}/jars/ http://central.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.313/aws-java-sdk-bundle-1.11.313.jar  \
  && wget -P ${SPARK_PACKAGE}/jars/ http://central.maven.org/maven2/org/postgresql/postgresql/42.2.2/postgresql-42.2.2.jar   \
  && wget -P ${SPARK_PACKAGE}/jars/ http://central.maven.org/maven2/mysql/mysql-connector-java/8.0.11/mysql-connector-java-8.0.11.jar


# create runtime image
FROM ubuntu:18.04

RUN apt-get update && apt-get install -y locales && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8

# Python3 pip
RUN apt-get install -y python3-pip

# Oracle Java 8 (JDK)
RUN apt-get install -y software-properties-common \
  && echo y | add-apt-repository ppa:webupd8team/java \
  && apt-get update \
  && echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections \
  && apt-get install -y oracle-java8-installer
ENV JAVA_HOME=/usr/lib/jvm/java-8-oracle

ENV SPARK_HOME="/spark"
ARG SPARK_PACKAGE="spark-2.3.0-bin-hadoop2.8.3"

WORKDIR ${SPARK_HOME}
# copy Spark distribution from build image
COPY --from=build "${SPARK_HOME}/${SPARK_PACKAGE}" .
# fix permissions
RUN chmod a+rw -R ${SPARK_HOME}

# clean up
RUN apt-get clean && apt-get autoremove
RUN rm -rf /var/lib/apt/lists/*

ENV PATH="${PATH}:${SPARK_HOME}/bin"
ENV PYSPARK_PYTHON=python3
ENV PYTHONIOENCODING=UTF-8
ENV SPARK_NO_DAEMONIZE=1

CMD ["bin/spark-shell"]
