class StartupsController < ApplicationController
  before_action :authenticate_founder!, except: %i[show index timeline_event_show paged_events]
  before_action :require_active_subscription, except: %i[index show timeline_event_show paged_events]

  # GET /startups
  def index
    load_startups
    load_filter_options
    @skip_container = true
    render layout: 'application_v2'
  end

  def show
    @skip_container = true
    @startup = Startup.friendly.find(params[:id])
    authorize @startup, :show?

    if params[:show_feedback].present?
      if current_founder.present?
        @feedback_to_show = @startup.startup_feedback.where(id: params[:show_feedback]).first if @startup.founder?(current_founder)
      else
        session[:referer] = request.original_url
        redirect_to new_user_session_path, alert: 'Please sign in to continue!'
        return
      end
    end

    @events_for_display = @startup.timeline_events_for_display(current_founder)
    @has_more_events = more_events?(@events_for_display, 1)
  end

  # GET /startups/:id/:event_title/:event_id
  def timeline_event_show
    # Reuse the startup action, because that's what this page also shows.
    show

    @timeline_event_for_og = @startup.timeline_events.find_by(id: params[:event_id])

    if @timeline_event_for_og.blank? || @timeline_event_for_og.hidden_from?(current_founder)
      raise_not_found
    else
      render 'show'
    end
  end

  # GET /startups/:id/events/:page
  def paged_events
    # Reuse the startup action, because that's what this page also shows.
    show
    @page = params[:page].to_i
    @has_more_events = more_events?(@events_for_display, @page)

    render layout: false
  end

  # GET /founder/startup/edit
  def edit
    @startup = current_founder.startup
    authorize @startup
  end

  # PATCH /founder/startup
  def update
    @startup = current_founder.startup
    authorize @startup

    if @startup.update(startup_params)
      flash[:success] = 'Startup details have been updated.'
      redirect_to @startup
    else
      render 'startups/edit'
    end
  end

  # POST /startup/level_up
  def level_up
    startup = current_founder.startup
    raise_not_found if startup.blank?
    authorize startup

    Startups::LevelUpService.new(startup).execute
    redirect_to(dashboard_founder_path(from: 'level_up', from_level: startup.level.number - 1))
  end

  private

  def more_events?(events, page)
    return false if events.count <= 20
    events.count > page * 20
  end

  # TODO: This method should be replaced with a Form to validate input from the filter.
  def load_startups
    category_id = params.dig(:startups_filter, :category)

    category_scope = if category_id.present? && StartupCategory.find_by(id: category_id).present?
      Startup.joins(:startup_categories).where(startup_categories: { id: category_id })
    else
      Startup.unscoped
    end

    level_id = params.dig(:startups_filter, :level)
    level_scope = level_id.present? ? Startup.where(level_id: level_id) : Startup.unscoped

    @startups = Startup.includes(:level, :startup_categories, :startups_startup_categories).admitted.approved.merge(category_scope).merge(level_scope).order(timeline_updated_on: 'DESC')
  end

  def load_filter_options
    @categories = StartupCategory.all
    @levels = Level.where('number > ?', 0).order(:number)
  end

  def startup_params
    params.require(:startup).permit(
      :legal_registered_name, :address, :pitch, :website, :email, :logo, :remote_logo_url, :facebook_link,
      :twitter_link, :product_name, :product_description,
      { startup_category_ids: [] }, { founders_attributes: [:id] },
      :registration_type, :presentation_link, :product_video_link, :wireframe_link, :prototype_link, :slug
    )
  end

  def startup_registration_params
    params.require(:startup).permit(:product_name)
  end
end
