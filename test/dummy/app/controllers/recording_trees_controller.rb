class RecordingTreesController < ApplicationController
  def index
    recordings = RecordingStudio::Recording
      .includes(:recordable)
      .where(trashed_at: nil)
      .order(:created_at)

    @roots = recordings.select { |recording| recording.parent_recording_id.nil? }
    @children_by_parent = recordings.group_by(&:parent_recording_id)
  end

  helper_method :recording_label

  private

  def recording_label(recording)
    recordable = recording.recordable
    type = recordable&.class&.name || recording.recordable_type

    name = if recordable.respond_to?(:name)
             recordable.name
           elsif recordable.respond_to?(:title)
             recordable.title
           else
             "(unnamed)"
           end

    "#{type}: #{name}"
  end
end
