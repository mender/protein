- [![Build Status](https://secure.travis-ci.org/mender/protein.png)](http://travis-ci.org/mender/protein)
- [![Code Climate](https://codeclimate.com/github/mender/protein.png)](https://codeclimate.com/github/mender/protein)
- [![Coverage Status](https://coveralls.io/repos/mender/protein/badge.png)](https://coveralls.io/r/mender/protein)

protein
=======

Protein is a Redis-backed Ruby library for creating and processing background jobs. 

## Features
1. Dynamic worker pool
2. Strategy based job processing, currently it has two strategies: 1 job per fork and multiple jobs in every fork
3. Middleware stack around job. You can to add rack-like middleware items into job processing cycle.

## Installation

Add this line to your application's `Gemfile`:

    gem 'protein'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install protein
    
## Usage

TODO

## Contributing

1. Fork it ( https://github.com/mender/protein/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
