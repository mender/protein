# encoding : utf-8
require 'tempfile'

class DownloadWork
  def self.perform(url)
    parsed = URI.parse(url)
    parsed = URI.parse('http://' + url) if parsed.scheme.nil?

    filename  = parsed.path.split('/').last
    extension = filename.present? ? File.extname(filename)             : ''
    basename  = filename.present? ? File.basename(filename, extension) : ''
    tempfile  = Tempfile.open([basename, extension], :encoding => 'ascii-8bit')
    begin
      timeout(10) do
        parsed.open { |f| tempfile.write(f.read) }
        Protein.logger.info "  [ DOWNLOAD #{url.underline} ]" if defined?(Protein)
      end
    ensure
      tempfile.close!
    end
  end
end