require 'logger'

module HAP
  module Log
    LOG_LVL = ENV['DEBUG'] ? :debug : :info

    def init_log()
      @log = Logger.new(STDOUT,
                        level: LOG_LVL,
                        progname: self,
                        formatter: proc {|severity, datetime, progname, msg|
                          "[#{datetime}][#{progname}] #{severity}: #{msg}\n"
                        })
    end

    def fatal(msg)
      @log.fatal(msg)
    end

    def error(msg)
      @log.error(msg)
    end

    def warn(msg)
      @log.warn(msg)
    end

    def info(msg)
      @log.info(msg)
    end

    def debug(msg)
      @log.debug(msg)
    end

    def log_debug?
      @log.debug?
    end
  end
end
