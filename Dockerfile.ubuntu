FROM ubuntu AS dev

RUN apt-get update -qq
RUN apt-get install -qq -y build-essential
RUN apt-get install -qq -y sudo
RUN apt-get install -qq -y git
RUN apt-get install -qq -y zsh

COPY entrypoint.sh /usr/local/bin
COPY entrypoint-user.sh /usr/local/bin

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]
