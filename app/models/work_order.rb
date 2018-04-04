require 'lims_client'
require 'event_message'
require 'securerandom'

# A work order, either in the progress of being defined (pending),
# or fully defined and waiting to be completed (active),
# or one that has been completed or cancelled (closed).
class WorkOrder < ApplicationRecord
  include AkerPermissionGem::Accessible

  belongs_to :work_plan

  belongs_to :process, class_name: "Aker::Process", optional: false
  has_many :work_order_module_choices, dependent: :destroy

  has_many :jobs

  after_initialize :create_uuid

  def create_uuid
    self.work_order_uuid ||= SecureRandom.uuid
  end

  def owner_email
    work_plan.owner_email
  end

  # The work order is in the 'active' state when not all jobs have been
  # compelted or cancelled
  def self.ACTIVE
    'active'
  end

  # The work order is in the 'broken' state when processing some operation
  # on it failed, and the correct state could not be recovered.
  # A broken work order can only be fixed by manual intervention.
  def self.BROKEN
    'broken'
  end

  # TODO: DEPRICATE
  # The work order is in the 'completed' state when all jobs have been completed
  def self.COMPLETED
    'completed'
  end

  # TODO: DEPRICATE
  # The work order is in the 'cancelled' state when the work order has been cancelled
  def self.CANCELLED
    'cancelled'
  end

  # The work order is in the 'concluded' state when the jobs have all been compelted or cancelled
  def self.CONCLUDED
    'concluded'
  end

  # The work order is in the 'queued' state when no jobs have been created
  def self.QUEUED
    'queued'
  end

  def total_tat
    process&.TAT
  end

  scope :active, -> { where(status: WorkOrder.ACTIVE) }
  # status is either set, product, proposal
  scope :pending, -> { where('status NOT IN (?)', not_pending_status_list)}
  scope :completed, -> { where(status: WorkOrder.COMPLETED) }
  scope :cancelled, -> { where(status: WorkOrder.CANCELLED) }
  scope :concluded, -> { where(status: WorkOrder.CONCLUDED) }

  def materials
    SetClient::Set.find_with_materials(set_uuid).first.materials
  end

  def has_materials?(uuids)
    return true if uuids.empty?
    return false if set_uuid.nil?
    uuids_from_work_order_set = SetClient::Set.find_with_materials(set_uuid).first.materials.map(&:id)
    uuids.all? do |uuid|
      uuids_from_work_order_set.include?(uuid)
    end
  end

  def self.not_pending_status_list
    [WorkOrder.ACTIVE, WorkOrder.BROKEN, WorkOrder.COMPLETED, WorkOrder.CANCELLED, WorkOrder.CONCLUDED]
  end

  def pending?
    # Returns true if the work order wizard has not yet been completed
    WorkOrder.not_pending_status_list.exclude?(status)
  end

  def active?
    status == WorkOrder.ACTIVE
  end

  def closed?
    # TODO: remove references to completed and cancelled
    status == WorkOrder.COMPLETED || status == WorkOrder.CANCELLED || status == WorkOrder.CONCLUDED
  end

  def queued?
    status == WorkOrder.QUEUED
  end

  def broken!
    update_attributes(status: WorkOrder.BROKEN)
  end

  def broken?
    status == WorkOrder.BROKEN
  end

  def concluded?
    status == WorkOrder.CONCLUDED
  end


# checks work_plan is not cancelled, work order is queued, and the first order in the work plan not to be closed
  def can_be_dispatched?
    (!work_plan.cancelled? && queued? && work_plan.work_orders.find {|o| !o.closed? }==self)
  end

  def original_set
    return nil unless original_set_uuid
    return @original_set if @original_set&.uuid==original_set_uuid
    begin
      @original_set = SetClient::Set.find(original_set_uuid).first
    rescue JsonApiClient::Errors::NotFound => e
      return nil
    end
  end

  def original_set=(orig_set)
    self.original_set_uuid = orig_set&.uuid
    @original_set = orig_set
  end

  def set
    return nil unless set_uuid
    return @set if @set&.uuid==set_uuid
    @set = SetClient::Set.find(set_uuid).first
  end

  def set=(set)
    self.set_uuid = set&.uuid
    @set = set
  end

  def finished_set
    return nil unless finished_set_uuid
    return @finished_set if @finished_set&.uuid==finished_set_uuid
    @finished_set = SetClient::Set.find(finished_set_uuid).first
  end

  def num_samples
    self.set && self.set.meta['size']
  end

  # Make sure we have a locked set in our set field.
  # Returns true if a set has been locked during this method.
  def finalise_set
    # If we already have an input set, and it is already locked, there is nothing to do
    return false if set&.locked

    if !set && !original_set
      # No set is linked to this order
      raise "No set selected for work order"
    end

    anylocked = false

    if set # We already have an input set, but it needs to be locked
      set.update_attributes(locked: true)
      @set = SetClient::Set.find(set_uuid).first # make sure the set is reloaded
      raise "Failed to lock set #{set.name}" unless set.locked
      anylocked = true
    elsif original_set.locked # Our original set is already locked, so we don't need to copy it
      self.set = original_set
    else # create a locked clone of the original set as our final input set
      self.set = original_set.create_locked_clone(name)
      anylocked = true
    end
    save!
    return anylocked
  end

  def create_editable_set
    raise "Work order already has input set" if set_uuid
    raise "Work order has no original set" unless original_set_uuid
    self.set = original_set.create_unlocked_clone(name)
    save!
    self.set
  end

  def name
    "Work Order #{id}"
  end

  def create_jobs
    # Raise exception if module names are not valid from BillingFacadeMock
    validate_module_names(module_choices)

    material_ids = SetClient::Set.find_with_materials(set_uuid).first.materials.map{|m| m.id}
    materials = all_results(MatconClient::Material.where("_id" => {"$in" => material_ids}).result_set)

    unless materials.all? { |m| m.attributes['available'] }
      raise "Some of the specified materials are not available."
    end

    containers = all_results(MatconClient::Container.where(
      "slots.material": {
        "$in": material_ids
        }
    ).result_set).uniq

    ActiveRecord::Base.transaction do
      containers.each do |container|
        Job.create!(container_uuid: container.id, work_order: self)
      end
    end
  end

  def send_to_lims
    create_jobs
    jobs.each(&:send_to_lims)
  end

  def all_results(result_set)
    results = result_set.to_a
    while result_set.has_next? do
      result_set = result_set.next
      results += result_set.to_a
    end
    results
  end

  def lims_data_for_get
    data = {work_order: {jobs: jobs.map(&:lims_data) }}
    unless data[:work_order].nil?
      data[:work_order][:status] = status
    end
    data
  end

  def selected_path
    path = []
    module_choices = WorkOrderModuleChoice.where(work_order_id: id)
    module_choices.each do |c|
      mod = Aker::ProcessModule.find(c.aker_process_modules_id)
      path.push({name: mod.name, id: mod.id})
    end
    path
  end

  def estimated_completion_date
    return nil unless dispatch_date && process
    dispatch_date + process.TAT
  end


  def generate_completed_and_cancel_event
    begin
      if closed?
        message = WorkOrderEventMessage.new(work_order: self, status: status)
        BrokerHandle.publish(message)
        BillingFacadeClient.send_event(self, status)
      else
        Rails.logger.error('Complete/cancel event cannot be generated from a work order that has not been completed.')
      end
    rescue => e
      Rails.logger.error e
      Rails.logger.error e.backtrace
    end
  end

  def generate_submitted_event
    begin
      if active?
        message = WorkOrderEventMessage.new(work_order: self, status: 'submitted')
        BrokerHandle.publish(message)
        BillingFacadeClient.send_event(self, 'submitted')
      else
        Rails.logger.error("Submitted event cannot be generated from a work order that is not active.")
      end
    rescue => e
      Rails.logger.error e
      Rails.logger.error e.backtrace
    end
  end

  def module_choices
    module_choices = []
    WorkOrderModuleChoice.where(work_order_id: id).order(:position).pluck(:aker_process_modules_id).each do |id|
      module_choices.push(Aker::ProcessModule.find(id).name)
    end
    module_choices
  end

  def validate_module_names(module_names)
    bad_modules = module_names.reject { |m| validate_module_name(m) }
    unless bad_modules.empty?
      raise "Process module could not be validated: #{bad_modules}"
    end
  end

  def validate_module_name(module_name)
    uri_module_name = module_name.gsub(' ', '_').downcase
    BillingFacadeClient.validate_process_module_name(uri_module_name)
  end

  # The next order in the work plan (or nil if there is none)
  def next_order
    WorkOrder.where(work_plan_id: work_plan_id, order_index: order_index+1).first
  end

end
