# frozen_string_literal: true

class DropApiRequestLogSummaries < ActiveRecord::Migration[8.1]
  COUNTS_TABLE = "recording_studio_api_api_request_day_summaries"
  LATENCY_TABLE = "recording_studio_api_api_request_latency_day_summaries"
  ROLLUP_VIEW = "recording_studio_api_api_request_day_metric_rollups"

  def up
    each_request_log_connection { |conn| drop_summary_tables(conn) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
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

  def drop_summary_tables(conn)
    conn.execute("DROP VIEW IF EXISTS #{conn.quote_table_name(ROLLUP_VIEW)}")
    conn.execute("DROP TABLE IF EXISTS #{conn.quote_table_name(LATENCY_TABLE)}")
    conn.execute("DROP TABLE IF EXISTS #{conn.quote_table_name(COUNTS_TABLE)}")
  end
end
