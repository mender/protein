# -*- encoding : utf-8 -*-
class Protein::Support
  include Singleton

  # TODO научиться удалять задачи определенного класса, а не только все
  def delete_jobs
    client.reset!
  end
  alias_method :clear_jobs, :delete_jobs

  def job_exists?(name = nil)
    jobs = client.redis.list(Protein::Client::QUEUE_KEY) || []

    jobs = jobs.select{ |job| job[:job_name] == name } if name.present?

    jobs.any?{ |job| client.job_exists?(job[:id]) }
  end
  alias_method :have_job?, :job_exists?

  def client
    Protein::Client.instance
  end
end

def bg
  Protein::Support.instance
end
