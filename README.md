[![Travis Build Status](https://img.shields.io/travis/Studiosity/grover.svg?style=flat)](https://travis-ci.org/Studiosity/grover)
[![Maintainability](https://api.codeclimate.com/v1/badges/37609653789bcf2c8d94/maintainability)](https://codeclimate.com/github/Studiosity/grover/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/37609653789bcf2c8d94/test_coverage)](https://codeclimate.com/github/Studiosity/grover/test_coverage)
[![Gem Version](https://badge.fury.io/rb/grover.svg)](https://badge.fury.io/rb/grover)

# Grover

A Ruby gem to transform HTML into PDFs using [Google Puppeteer](https://github.com/GoogleChrome/puppeteer)
and [Chromium](https://www.chromium.org/Home).

![Grover](/Grover.jpg "Grover")

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'grover'
```

### Google Puppeteer
```bash
npm install puppeteer
``` 


## Usage
```ruby
# Grover.new accepts a URL or inline HTML and optional parameters for Puppeteer
grover = Grover.new('https://google.com', format: 'A4')

# Get an inline PDF
pdf = grover.to_pdf

# Options can be provided through meta tags
Grover.new('<html><head><meta name="grover-page_ranges" content="1-3"')
Grover.new('<html><head><meta name="grover-margin-top" content="10px"')
# N.B. options are underscore case, and sub-options separated with a dash
# N.B. #2 all options can be overwritten, including `emulate_media` and `display_url` 
```


## Configuration
Grover can be configured to adjust the layout of the resulting PDF. 
For available options, see https://github.com/GoogleChrome/puppeteer/blob/v1.7.0/docs/api.md#pagepdfoptions

Also available are the `emulate_media`, `cache` and `timeout` options.
 
```ruby
# config/initializers/grover.rb
Grover.configure do |config|
  config.options = {
    format: 'A4',
    margin: {
      top: '5px',
      bottom: '10cm'
    },
    prefer_css_page_size: true,
    emulate_media: 'screen',
    cache: false,
    timeout: 0 # Timeout in ms. A value of `0` means 'no timeout'
  }
end
```

#### Page URL for middleware requests (or passing through raw HTML)
If you want to have the header or footer display the page URL, Grover requires that this is passed through via the
`display_url` option. This is because the page URL is not available in the raw HTML!

For Rack middleware conversions, the original request URL (without the .pdf extension) will be passed through and
assigned to `display_url` for you. You can of course override this by using a meta tag in the downstream HTML response.

For raw HTML conversions, if the `display_url` is not provided `http://example.com` will be used as the default.

#### Header and footer templates
Should be valid HTML markup with following classes used to inject printing values into them:
* `date` formatted print date
* `title` document title
* `url` document location
* `pageNumber` current page number
* `totalPages` total pages in the document  


## Middleware
Grover comes with a middleware that allows users to get a PDF view of
any page on your site by appending .pdf to the URL.

### Middleware Setup
**Non-Rails Rack apps**
```ruby
# in config.ru
require 'grover'
use Grover::Middleware
```

**Rails apps**
```ruby
# in application.rb
require 'grover'
config.middleware.use Grover::Middleware
```


## Cover pages
Since the header/footer for Puppeteer is configured globally, displaying of front/back cover
pages (with potentially different headers/footers etc) is not possible.

To get around this, Grover's middleware allows you to specify relative paths for the cover page contents
via `front_cover_path` and `back_cover_path` either via the global configuration, or via meta tags.
These paths (with query parameters) are then requested from the downstream app.

The cover pages are converted to PDF in isolation, and then combined together with the original PDF response,
before being returned back up through the Rack stack. 
 
_N.B_ To simplify things, the same request method and body are used for the cover page requests.

```ruby
# config/initializers/grover.rb
Grover.configure do |config|
  config.options = {
    front_cover_path: '/some/global/cover/page?foo=bar'
  }
end
```

Or via the meta tags in the original response:
```HTML
<html>
  <head>
    <meta name="grover-back_cover_path" content="/back/cover/page?bar=baz" />
  </head>
  ...
</html>    
```
 

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Studiosity/grover.

Note that spec tests are appreciated to minimise regressions. Before submitting a PR, please ensure that:
 
```bash
$ rspec
```
and

```bash
$ rubocop
```
both succeed


## Special mention
Thanks are given to the great work done in the [PDFKit project](https://github.com/pdfkit/pdfkit).
The middleware and HTML preprocessing components were used heavily in the implementation of Grover.  


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
