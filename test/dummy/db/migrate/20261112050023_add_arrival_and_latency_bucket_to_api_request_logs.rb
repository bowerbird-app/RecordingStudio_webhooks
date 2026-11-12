# frozen_string_literal: true

class AddArrivalAndLatencyBucketToApiRequestLogs < ActiveRecord::Migration[8.1]
  def up
    each_request_log_connection { |conn| add_arrival_columns(conn) }
  end

  def down
    each_request_log_connection { |conn| remove_arrival_columns(conn) }
  end

  private

  def each_request_log_connection
    seen = []
    [connection, logging_connection].compact.each do |conn|
      identity = [conn.pool.db_config.name, conn.raw_connection.object_id]
      next if seen.include?(identity)

      seen << identity
      yield conn
    end
  end

  def logging_connection
    return unless defined?(RecordingStudioApi::ApiRequestLog)

    RecordingStudioApi::ApiRequestLog.connection
  rescue StandardError
    nil
  end

  def add_arrival_columns(conn)
    table = "recording_studio_api_api_request_logs"
    return unless conn.data_source_exists?(table)

    conn.add_column table, :arrived_at, :datetime unless conn.column_exists?(table, :arrived_at)
    conn.add_column table, :latency_bucket_ms, :integer unless conn.column_exists?(table, :latency_bucket_ms)
    conn.change_column_default table, :arrived_at, from: nil, to: -> { "clock_timestamp()" }
  end

  def remove_arrival_columns(conn)
    table = "recording_studio_api_api_request_logs"
    return unless conn.data_source_exists?(table)

    conn.remove_column table, :latency_bucket_ms if conn.column_exists?(table, :latency_bucket_ms)
    conn.remove_column table, :arrived_at if conn.column_exists?(table, :arrived_at)
  end
end
