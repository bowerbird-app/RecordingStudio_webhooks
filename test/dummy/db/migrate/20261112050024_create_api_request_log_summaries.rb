# frozen_string_literal: true

class CreateApiRequestLogSummaries < ActiveRecord::Migration[8.1]
  COUNTS_TABLE = "recording_studio_api_api_request_day_summaries"
  LATENCY_TABLE = "recording_studio_api_api_request_latency_day_summaries"
  ROLLUP_VIEW = "recording_studio_api_api_request_day_metric_rollups"

  def up
    each_request_log_connection { |conn| create_summary_tables(conn) }
  end

  def down
    each_request_log_connection { |conn| drop_summary_tables(conn) }
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

  def create_summary_tables(conn)
    RecordingStudioLogs::Schema.install_runs!(conn)

    unless conn.data_source_exists?(COUNTS_TABLE)
      conn.create_table COUNTS_TABLE, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.date :day, null: false
        t.uuid :root_recording_id
        t.string :api_key, null: false
        t.string :route_name, null: false
        t.string :request_method, null: false
        t.integer :status_code, null: false
        t.boolean :rate_limited, null: false, default: false
        t.bigint :request_count, null: false, default: 0
        t.bigint :duration_sum_ms, null: false, default: 0
        t.bigint :duration_max_ms, null: false, default: 0
        t.timestamps
      end
      RecordingStudioLogs::Schema.summary_index(
        COUNTS_TABLE,
        %i[day root_recording_id api_key route_name request_method status_code rate_limited],
        name: "index_rs_api_request_day_summaries_identity",
        connection: conn
      )
      conn.add_index COUNTS_TABLE, %i[api_key day], name: "index_rs_api_request_day_summaries_on_api_and_day"
      conn.add_index COUNTS_TABLE, %i[root_recording_id day], name: "index_rs_api_request_day_summaries_on_root_and_day"
    end

    unless conn.data_source_exists?(LATENCY_TABLE)
      conn.create_table LATENCY_TABLE, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.date :day, null: false
        t.uuid :root_recording_id
        t.string :api_key, null: false
        t.string :route_name, null: false
        t.string :request_method, null: false
        t.integer :status_code, null: false
        t.integer :latency_bucket_ms, null: false
        t.bigint :request_count, null: false, default: 0
        t.timestamps
      end
      RecordingStudioLogs::Schema.summary_index(
        LATENCY_TABLE,
        %i[day root_recording_id api_key route_name request_method status_code latency_bucket_ms],
        name: "index_rs_api_request_latency_day_summaries_identity",
        connection: conn
      )
      conn.add_index LATENCY_TABLE, %i[api_key day], name: "index_rs_api_request_latency_day_summaries_on_api_and_day"
      conn.add_index LATENCY_TABLE, %i[root_recording_id day], name: "index_rs_api_request_latency_day_summaries_on_root_and_day"
    end

    create_rollup_view(conn)
  end

  def create_rollup_view(conn)
    return if conn.data_source_exists?(ROLLUP_VIEW)

    quoted_view = conn.quote_table_name(ROLLUP_VIEW)
    quoted_source = conn.quote_table_name(COUNTS_TABLE)
    conn.execute(<<~SQL.squish)
      CREATE VIEW #{quoted_view} AS
      SELECT
        day AS metric_date,
        api_key,
        route_name,
        request_method,
        (status_code / 100) AS status_class,
        SUM(request_count)::bigint AS request_count,
        SUM(CASE WHEN rate_limited OR status_code = 429 THEN request_count ELSE 0 END)::bigint AS rate_limited_count,
        SUM(CASE WHEN status_code BETWEEN 400 AND 499 THEN request_count ELSE 0 END)::bigint AS client_error_count,
        SUM(CASE WHEN status_code BETWEEN 500 AND 599 THEN request_count ELSE 0 END)::bigint AS server_error_count,
        SUM(request_count)::bigint AS duration_count,
        SUM(duration_sum_ms)::bigint AS duration_sum_ms,
        MAX(duration_max_ms)::integer AS duration_max_ms
      FROM #{quoted_source}
      GROUP BY day, api_key, route_name, request_method, (status_code / 100)
    SQL
  end

  def drop_summary_tables(conn)
    conn.execute("DROP VIEW IF EXISTS #{conn.quote_table_name(ROLLUP_VIEW)}")
    conn.drop_table LATENCY_TABLE if conn.data_source_exists?(LATENCY_TABLE)
    conn.drop_table COUNTS_TABLE if conn.data_source_exists?(COUNTS_TABLE)
  end
end
