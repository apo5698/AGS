# frozen_string_literal: true

# Grade items are generated from a rubric item, and associated with a participant.
class GradeItem < ApplicationRecord
  attr_accessor :content

  ################
  # Enumerations #
  ################

  enum status: {
    inactive: 'Inactive',
    success: 'Success',
    resolved: 'Resolved',
    unresolved: 'Unresolved',
    error: 'Error',
    no_submission: 'No submission'
  }

  ################
  # Associations #
  ################

  belongs_to :participant
  belongs_to :rubric_item, class_name: 'Rubrics::Item::Base'

  ###############
  # Validations #
  ###############

  # Negative grade does not make sense.
  validates :point, numericality: { greater_than_or_equal_to: 0 }

  #############
  # Callbacks #
  #############

  # Set default status if not specified.
  after_initialize { inactive! if status.nil? }

  # Ask participant to fetch latest grades and feedbacks
  after_save { participant.fetch }

  ###############
  # Delegations #
  ###############

  delegate :<=>, :name, to: :participant
  delegate :to_s, :filename, :maximum_points, to: :rubric_item

  def feedback=(feedback)
    super(Helli::SeparatedString.new(feedback).to_s)
  end

  # Resets the grade item the initial state (empty).
  def reset
    update!({ status: :inactive, stdout: '', stderr: '', error: 0, point: 0, feedback: '' })
  end

  # Returns the attachment with the same filename within its participant's submissions.
  #
  # @return [ActiveStorage::Attachment, nil]
  def attachment
    participant.attachment(rubric_item.filename)
  end

  # Accepts a series of options and then invokes #run per its rubric type.
  #
  # @param [Hash, ActionController::Parameters] options
  # @return [GradeItem] self
  def run(options)
    # No submission per Moodle grade worksheet.
    if participant.no_submission?
      update!(attributes_preset_for(:no_submission))
      return self
    end

    if attachment.nil?
      update!(attributes_preset_for(:no_matched_attachment))
      return self
    end

    # Downloading strategy:
    #   1. Download files to a temporary directory
    #   2. Keep them for a period of time (default 4 hours)
    #   3. Delete using cron jobs (sidekiq)
    path = Helli::Attachment.download_one(attachment)
    captures, error_count = rubric_item.run(path, options)

    @content = File.read(path)

    # Assigns attributes before grading
    self.status = :success
    self.stdout = captures[0]
    # Removes JAVA_TOOL_OPTIONS.
    # See https://devcenter.heroku.com/articles/java-support#environment
    self.stderr = captures[1].split("\n").grep_v(/.*JAVA_TOOL_OPTIONS.*/).join("\n")
    self.exitstatus = captures[2].exitstatus
    self.error = error_count
    self.point = 0

    new_feedback = Helli::SeparatedString.new

    rubric_item.criteria.each do |c|
      c.grade_item = self
      new_feedback << c.validate
    end

    self.feedback = new_feedback

    # Grade cannot be negative
    self.point = 0 if point.negative?

    save!
    self
  end

  # An error message indicating that a manual resolution is needed.
  def resolve_manually(msg)
    "#{msg}. Please resolve manually."
  end

  # @param [Symbol] type
  # @return [Hash]
  def attributes_preset_for(type)
    case type
    when :no_submission
      { status: :no_submission, feedback: 'No submission' }
    when :no_matched_attachment
      { status: :unresolved, feedback: resolve_manually('No matched file') }
    else
      raise "Unknown attributes type: #{type}"
    end
  end
end
