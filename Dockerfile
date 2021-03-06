# aker-work-orders
FROM ruby:2.3.1

# Update package list and install required packages
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev

# https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions
RUN curl -sL https://deb.nodesource.com/setup_6.x | bash -
RUN apt-get install -y nodejs

RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get install yarn

# Create and go to the working directory - https://docs.docker.com/engine/reference/builder/#workdir
WORKDIR /code

# Install phantomjs - required for tests - https://www.npmjs.com/package/phantomjs-prebuilt
# Using --unsafe-perm because: https://github.com/Medium/phantomjs/issues/707
RUN npm install -g phantomjs-prebuilt --unsafe-perm

# Add the package.json and package-lock.json file
ADD package.json /code/package.json
ADD yarn.lock /code/yarn.lock

# Install node modules required
RUN yarn install

# Add the Gemfile and .lock file
ADD Gemfile /code/Gemfile
ADD Gemfile.lock /code/Gemfile.lock

# Install bundler - http://bundler.io/
RUN gem install bundler

# Install gems required by project
RUN bundle install

# Add the wait-for-it file to utils
ADD https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh /utils/wait-for-it.sh
RUN chmod u+x /utils/wait-for-it.sh

# Add the docker-entrypoint file to utils
ADD https://raw.githubusercontent.com/pjvv/docker-entrypoint/master/docker-entrypoint.sh /utils/docker-entrypoint.sh
RUN chmod u+x /utils/docker-entrypoint.sh

# Add all remaining contents to the image
ADD . /code
