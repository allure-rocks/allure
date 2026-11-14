# frozen_string_literal: true

# The current user's gear, with lifetime totals maintained by
# `Equipments::Totals`. Owner-only throughout: every lookup is scoped through
# `current_user`, so another user's id yields 404, never 403.
class EquipmentsController < ApplicationController
  before_action :set_equipment, only: %i[show edit update destroy refresh]
  before_action :set_equipment_types, only: %i[new create edit update]

  def index
    @equipments = current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
  end

  def show
    @workouts = @equipment.workouts.includes(:sport).order(started_at: :desc, id: :desc)
  end

  def new
    @equipment = current_user.equipments.new(is_active: true)
  end

  def create
    @equipment = current_user.equipments.new(equipment_params)
    if @equipment.save
      redirect_to equipments_path, notice: t("equipments.create.success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @equipment.update(equipment_params)
      redirect_to equipment_path(@equipment), notice: t("equipments.update.success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @equipment.destroy!
    redirect_to equipments_path, notice: t("equipments.destroy.success")
  end

  def refresh
    Equipments::Totals.refresh(@equipment)
    redirect_to equipment_path(@equipment), notice: t("equipments.refresh.success")
  end

  private

  def set_equipment
    @equipment = current_user.equipments.find_by_short_id!(params[:id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def set_equipment_types
    scope = EquipmentType.order(:label)
    scope = scope.where(is_active: true) if action_name.in?(%w[new create])
    @equipment_types = scope
  end

  def equipment_params
    params.require(:equipment).permit(:label, :description, :equipment_type_id, :is_active)
  end
end
