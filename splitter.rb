class Splitter
  attr_accessor :day_in_rule, :tmr_com_work_day, :tmr_law_work_day, :tmr_normal_work_day
  def initialize data
    # Basic info
    @data = data
    @current_date = data[:current_date]
    @date = data[:date]
    @date_info = data[:date_info]
    @time_cards = data[:time_cards]
    @holiday = data[:holiday]
    @work_form = data[:work_form]
    @is_day = data[:is_day]
    @is_business = data[:is_business]
    @pre_overtimes = data[:pre_overtimes]

    # User setting
    @hour_work_on_day = data[:hour_work_on_day]
    @leave_tmp = data[:leave_tmp]
    @leave_start = data[:leave_start]
    @leave_end = data[:leave_end]
    @is_flex_flexible = data[:is_flex_flexible]

    # Shop setting
    @add_outgoing = data[:add_outgoing]
    @company_holiday_ot = data[:company_holiday_ot]

    # Company setting
    @minus_working_day = data[:minus_working_day]
    @overtime_shift_mode = data[:overtime_shift_mode]

    # Request day off in day
    @count_day_off_to_work_time = data[:count_day_off_to_work_time]
    @count_day_off_to_OT = data[:count_day_off_to_OT]

    # Hour with types
    @night_hours = data[:night_hours]
    special_hours = data[:special_hours]
    @special_hour_1 = special_hours[:special_1]
    @special_hour_2 = special_hours[:special_2]

    # Late early info
    @ignore_late_times = data[:ignore_late_times]
    @ignore_late_time = data[:ignore_late_time]
    
    # Auto break
    @auto_break_by_timeline = data[:auto_break_by_timeline]
    @auto_break_by_time = data[:auto_break_by_time]
    @master_break = data[:master_break]

    # Work day info from last day
    @com_work_day = data[:com_work_day]
    @law_work_day = data[:law_work_day]
    @normal_work_day = data[:normal_work_day]

    # Plan info
    @plan_info = data[:plan_info]
    @normal_work_day ||= @plan_info[:normal_work_day]
    @planned_work_day = @plan_info[:planned_work_day]
    @minus_plan_day_sdo = @plan_info[:minus_plan_day_sdo]
    @off_all_day = @plan_info[:off_all_day]
    @day_off_used = @plan_info[:day_off_used]
    @rdo_working_rate = @plan_info[:rdo_working_rate]

    # OT info
    @max_day = data[:max_day]
    @max_day = [@plan_info[:plan_time], @max_day].max if @work_form == 'deformation'
    @time_to_in_rule = data[:time_to_in_rule]
    @time_to_out_rule = [[data[:remaining_max_week], @max_day].min, 0].max

    # Split time card
    @time_card_info = split_time_card
  end

  def execute
    outgoing_time = @time_card_info[:outgoing_time] / 1.hour
    @total_salary_off_time = @plan_info[:total_salary_off_time].to_f
    plan_time = @plan_info[:plan_time] / 1.hour
    tc_chunks = @time_card_info[:tc_chunks]
    total_time = @time_card_info[:total_time] / 1.hour

    analyzed_pkg = chunk_analyzer(tc_chunks, @auto_break_by_timeline)
    if @auto_break_by_timeline
      tc_chunks = auto_break_by_timeline(tc_chunks, analyzed_pkg)
      analyzed_pkg = chunk_analyzer(tc_chunks)
    end
    work_time = CustomDate.calc_time_chunks(tc_chunks) / 1.hour
    late_early = calc_late_early

    company_holiday_chunks, law_holiday_chunks, night_hour_chunks, special_hour_1_chunks, special_hour_2_chunks = analyzed_pkg[:by_def]
    ot_night_chunks, ot_special_1_chunks, ot_special_2_chunks = analyzed_pkg[:ot_related]
    ot_in_rule, ot_out_rule, actual_in_rule, hour_work_on_comp, hour_work_on_law = analyzed_pkg[:hours]
    total_ot = ot_in_rule + ot_out_rule

    @total_salary_off_time /= 1.hour
    working_hours_actual = @count_day_off_to_work_time ? work_time + @total_salary_off_time : work_time
    number_hour_relax = @add_outgoing ? total_time - work_time : total_time - work_time - outgoing_time
    hour_work_on_holiday = hour_work_on_comp + hour_work_on_law
    hour_work_on_normal = working_hours_actual - hour_work_on_holiday
    
    all_holiday_chunks = company_holiday_chunks + law_holiday_chunks
    night_hour_holiday = CustomDate.calc_overlapped_time_by_arrays(all_holiday_chunks, night_hour_chunks) / 1.hour
    total_night_work_hours = CustomDate.calc_time_chunks(night_hour_chunks) / 1.hour
    night_hour_normal = total_night_work_hours - night_hour_holiday
    total_hours_ot_out_rule_night = CustomDate.calc_time_chunks(ot_night_chunks) / 1.hour
    ot_out_rule_normal = ot_out_rule - total_hours_ot_out_rule_night
    special_work_hour_first = CustomDate.calc_time_chunks(special_hour_1_chunks) / 1.hour
    special_work_hour_second = CustomDate.calc_time_chunks(special_hour_2_chunks) / 1.hour
    out_rule_special_work_hour_first = CustomDate.calc_time_chunks(ot_special_1_chunks) / 1.hour
    out_rule_special_work_hour_second = CustomDate.calc_time_chunks(ot_special_2_chunks) / 1.hour

    # Number working day
    @normal_work_day ||= tc_chunks.present? && !(@com_work_day || @law_work_day)
    com_working_day = @com_work_day ? 1 : 0
    law_working_day = @law_work_day ? 1 : 0
    normal_working_day = @normal_work_day ? 1 : 0

    holiday_working_day = com_working_day + law_working_day
    normal_working_day = [(normal_working_day - @rdo_working_rate.to_f).round(CommonConstant::ROUND_3), 0].max if @minus_working_day
    total_working_day = normal_working_day + holiday_working_day

    # Number holiday
    number_holiday = @holiday[0].count { |k, v| v }
    day_off_used = @day_off_used.to_f.round(CommonConstant::ROUND_3)
    hour_off_used = @plan_info[:hour_off_used].to_f / 1.hour
    total_year_off_time = @plan_info[:total_year_off_time].to_f / 1.hour

    # Plan hour
    @planned_work_day ||= !plan_time.zero? && !@minus_plan_day_sdo
    absent_from_work = !@off_all_day && @planned_work_day && !@normal_work_day && !@com_work_day && !@law_work_day && @date < @current_date
    number_planned_work_day = @planned_work_day ? 1 : 0
    number_day_off = absent_from_work ? 1 : 0

    # For flex staff
    if @work_form == 'flex'
      number_planned_work_day = number_holiday.zero? && !@minus_plan_day_sdo ? 1 : 0
      plan_time *= number_planned_work_day if @is_day
      number_day_off = 0
    end

    if @is_business && !@is_day
      number_planned_work_day = number_holiday.zero? && !@minus_plan_day_sdo ? 1 : 0
    end

    # Leave temp
    plan_day_leave_temp = @leave_tmp && @date >= @leave_start && @date <= @leave_end ? number_planned_work_day : 0

    # working_hour_lack
    working_hour_lack = 0.0
    working_hour_lack = [plan_time - working_hours_actual, 0].max if !@is_flex_flexible
    pre_ot_request_approved = pre_ot_request_approved_calc(@date)

    #=================Budget#=================
    # calc plan OT
    night_plan_chunks = night_hour_plan_chunks @plan_info[:plan_for_calc]
    total_night_hour_plan = CustomDate.calc_time_chunks(night_plan_chunks) / 1.hour
    # calc day working target
    plan_and_real_day = number_planned_work_day > 0 ? number_planned_work_day : total_working_day
    #=================Budget#=================

    result = {
      plan_info: @plan_info,
      time_card_info: @time_card_info,

      working_hours_actual: working_hours_actual,
      number_hour_outgoing: outgoing_time,
      number_hour_relax: number_hour_relax,
      total_salary_off_time: @total_salary_off_time,

      working_hour_plan_in_rule: plan_time,
      working_day_plan_in_rule: number_planned_work_day,
      late_early: late_early,

      total_night_work_hours: total_night_work_hours,
      night_hour_holiday: night_hour_holiday,
      night_hour_normal: night_hour_normal,
      total_hours_ot_out_rule_night: total_hours_ot_out_rule_night,
      ot_out_rule_normal: ot_out_rule_normal,
      total_night_hour_plan: total_night_hour_plan,

      special_work_hour_first: special_work_hour_first,
      special_work_hour_second: special_work_hour_second,
      out_rule_special_work_hour_first: out_rule_special_work_hour_first,
      out_rule_special_work_hour_second: out_rule_special_work_hour_second,

      hour_work_on_comp: hour_work_on_comp,
      hour_work_on_law: hour_work_on_law,
      hour_work_on_holiday: hour_work_on_holiday,
      hour_work_on_normal: hour_work_on_normal,

      com_working_day: com_working_day,
      law_working_day: law_working_day,
      holiday_working_day: holiday_working_day,
      normal_working_day: normal_working_day,
      total_working_day: total_working_day,
      number_day_off: number_day_off,
      number_holiday: number_holiday,

      actual_in_rule: actual_in_rule,
      ot_in_rule: ot_in_rule,
      ot_out_rule: ot_out_rule,
      total_ot: total_ot,
      day_in_rule: @day_in_rule,
      
      total_year_off_time: total_year_off_time,
      day_off_used: day_off_used,
      hour_off_used: hour_off_used,
      plan_day_leave_temp: plan_day_leave_temp,
      working_hour_lack: working_hour_lack,
      plan_and_real_day: plan_and_real_day,
      pre_ot_request_approved: pre_ot_request_approved
    }

    if @data[:has_status_working]
      status_workings = {}
      status_workings = StatusWorkings.new(@data.merge(result)).execute
      result.merge!({ status_workings: status_workings })
    end
    result
  end

  def chunk_analyzer(tc_chunks, for_auto_break = nil)
    all_chunks = basic_chunks(tc_chunks)
    today_begin, today_end, tmr_begin, tmr_end = @date_info
    company_holiday_chunks, law_holiday_chunks, night_hour_chunks, special_hour_1_chunks, special_hour_2_chunks = all_chunks[:by_def]
    today_tc_chunks, tmr_tc_chunks = all_chunks[:by_day]

    # Remove law holiday and company holiday chunks from ot calculation
    ot_calc_chunks = (today_tc_chunks + tmr_tc_chunks) - law_holiday_chunks
    ot_calc_chunks -= company_holiday_chunks unless @company_holiday_ot

    # OT calc starts
    
    hour_work_on_comp = CustomDate.calc_time_chunks(company_holiday_chunks)
    hour_work_on_law = CustomDate.calc_time_chunks(law_holiday_chunks)
    time_to_in_rule = @time_to_in_rule
    time_to_out_rule = @time_to_out_rule
    time_to_out_rule = [time_to_out_rule - hour_work_on_law, 0].max if @law_work_day
    time_to_out_rule = [time_to_out_rule - hour_work_on_comp, 0].max if @com_work_day && !@company_holiday_ot
    actual_in_rule = 0
    ot_out_rule = 0
    ot_in_rule = 0
    @day_in_rule = 0
    
    # Calculate day off hour for OT
    unless @total_salary_off_time.zero? || !@count_day_off_to_OT
      in_rule_salary_off_time = @plan_info[:in_rule_salary_off_time]
      @day_in_rule = [@total_salary_off_time, time_to_out_rule].min
      actual_in_rule += [in_rule_salary_off_time, time_to_out_rule].min
      ot_in_rule = [@day_in_rule - in_rule_salary_off_time, 0].max
      if @is_flex_flexible && !@is_day
        ot_in_rule = [@day_in_rule - time_to_in_rule, 0].max
        time_to_in_rule = 0 unless ot_in_rule.zero?
      end
      ot_out_rule = [@total_salary_off_time - time_to_out_rule, 0].max
      time_to_out_rule = 0 unless ot_out_rule.zero?
    end

    actual_in_rule_chunks = []
    ot_in_rule_chunks = []
    ot_out_rule_chunks = []
    unless @is_flex_flexible
      plan_chunks = @plan_info[:plan_for_calc]
      in_shift = CustomDate.array_of_overlapped(ot_calc_chunks, plan_chunks, true)
      out_shift = CustomDate.array_of_not_overlapped(ot_calc_chunks, plan_chunks)
      in_out_shift = (in_shift + out_shift)
      in_out_shift.sort_by! { |a| a[0] } unless @overtime_shift_mode
      in_out_shift.each do |chunk|
        unless time_to_out_rule.zero?
          @day_in_rule += CustomDate.calc_time_chunks([chunk])
          if @day_in_rule > time_to_out_rule
            ot_point = chunk[1] - (@day_in_rule - time_to_out_rule)
            ot_out_rule_chunks << [ot_point, chunk[1]]
            @day_in_rule = time_to_out_rule
            time_to_out_rule = 0
            next if ot_point <= chunk[0]
            time_chunk = [chunk[0], ot_point]
            chunk[2] ? actual_in_rule_chunks << time_chunk : ot_in_rule_chunks << time_chunk
          else
            time_chunk = chunk[0..1]
            chunk[2] ? actual_in_rule_chunks << time_chunk : ot_in_rule_chunks << time_chunk
          end
        else
          ot_out_rule_chunks << chunk[0..1]
        end
      end
    else
      in_rule_point = out_rule_point = nil
      ot_calc_chunks.each do |chunk|
        @day_in_rule += CustomDate.calc_time_chunks([chunk])
        if in_rule_point.blank?
          in_rule = [@day_in_rule - time_to_in_rule, 0].max
          in_rule_point = chunk[1] - in_rule unless in_rule.zero?
        end
        out_rule = [@day_in_rule - time_to_out_rule, 0].max
        unless out_rule.zero?
          out_rule_point = chunk[1] - out_rule
          @day_in_rule = time_to_out_rule
          break
        end
      end
      out_rule_point ||= tmr_end
      in_rule_point ||= out_rule_point
      ot_in_rule_chunks = CustomDate.array_of_overlapped(ot_calc_chunks, [[in_rule_point, out_rule_point]])
      ot_out_rule_chunks = CustomDate.array_of_overlapped(ot_calc_chunks, [[out_rule_point, tmr_end]])
    end

    return {
      by_def: [company_holiday_chunks, law_holiday_chunks, night_hour_chunks],
      ot: [ot_in_rule_chunks]
    } if for_auto_break

    ot_out_rule += CustomDate.calc_time_chunks(ot_out_rule_chunks)
    actual_in_rule += CustomDate.calc_time_chunks(actual_in_rule_chunks)
    ot_in_rule += CustomDate.calc_time_chunks(ot_in_rule_chunks)
    ot_night_chunks = CustomDate.array_of_overlapped(night_hour_chunks, ot_out_rule_chunks)
    ot_special_1_chunks = CustomDate.array_of_overlapped(special_hour_1_chunks, ot_out_rule_chunks)
    ot_special_2_chunks = CustomDate.array_of_overlapped(special_hour_2_chunks, ot_out_rule_chunks)
    ot_in_rule /= 1.hour
    ot_out_rule /= 1.hour
    actual_in_rule /= 1.hour
    hour_work_on_comp /= 1.hour
    hour_work_on_law /= 1.hour
    ot_in_rule = ot_out_rule = 0 if @is_day && @is_flex_flexible
    {
      by_def: [company_holiday_chunks, law_holiday_chunks, night_hour_chunks, special_hour_1_chunks, special_hour_2_chunks],
      ot: [ot_in_rule_chunks, ot_out_rule_chunks],
      ot_related: [ot_night_chunks, ot_special_1_chunks, ot_special_2_chunks],
      hours: [ot_in_rule, ot_out_rule, actual_in_rule, hour_work_on_comp, hour_work_on_law]
    }
  end

  def auto_break_by_timeline tc_chunks, analyzed_pkg
    work_time = CustomDate.calc_time_chunks(tc_chunks) / 1.hour
    ab_time, ab_amount = master_break_by_timeline(work_time)
    return tc_chunks unless !(ab_time.to_f * ab_amount.to_f).zero? && tc_chunks.present?

    # Prepare tc_chunks for auto_break according to the priority noted in task JINJER-10227
    all_pkg = analyzed_pkg[:by_def] + analyzed_pkg[:ot]
    auto_break_pkg = ab_pkg(tc_chunks, all_pkg)
   
    # Specify auto_break time
    total = 0
    break_array = []
    break_finished =  false
    auto_break_pkg.each do |chunk|
      next if break_finished
      total += CustomDate.calc_time_chunks([chunk])
      if total > ab_amount
        break_array << [chunk[0], chunk[1] - (total - ab_amount)]
        break_finished = true
      else
        break_array << chunk
      end
    end
    CustomDate.array_of_not_overlapped(tc_chunks, break_array.sort_by { |a| a[0] })
  end

  # Recursive method to get the best possible chunks
  # first_pkg: pkg that do not overlap with any higher pkg -> ab first choice
  # second_pkg: pkg that overlap with the next higher pkg -> ab second choice
  # third_pkg: pkg that do not overlap with the next higher pkg -> ab last choice
  def ab_pkg(remainings, all_pkg)
    return remainings if all_pkg.blank? || remainings.blank?
    splitter = CustomDate.merge_overlapped_inside_array(all_pkg.sum { |chunk| chunk }.sort_by { |a| a[0] })
    first_pkg = CustomDate.array_of_not_overlapped(remainings, splitter)
    first_pkg_remainings = CustomDate.array_of_overlapped(remainings, splitter)
    splitter = all_pkg.shift
    all_pkg_dup = all_pkg.dup
    second_pkg = CustomDate.array_of_overlapped(remainings, splitter)
    third_pkg = CustomDate.array_of_not_overlapped(first_pkg_remainings, splitter)
    first_pkg + ab_pkg(second_pkg, all_pkg) + ab_pkg(third_pkg, all_pkg_dup)
  end

  def basic_chunks tc_chunks
    today_begin, today_end, tmr_begin, tmr_end = @date_info
    result_pkg = [[], [], [], [], []]
    all_pkg = [[[today_begin, today_end]], [[tmr_begin, tmr_end]], @night_hours, @special_hour_1, @special_hour_2]
    all_pkg.each_with_index do |pkg, idx|
      result_pkg[idx] += CustomDate.array_of_overlapped(pkg, tc_chunks)
    end
    holiday_pkg = holiday_chunks(result_pkg[0], result_pkg[1])
    by_def = holiday_pkg + [result_pkg[2], result_pkg[3], result_pkg[4]]
    by_day = result_pkg[0], result_pkg[1]
    {
      by_def: by_def,
      by_day: by_day,
    }
  end

  def holiday_chunks today_tc_chunks, tmr_tc_chunks
    result = [[], []]
    return result if today_tc_chunks.blank? && tmr_tc_chunks.blank?
    today_holiday = @holiday[0]
    tmr_holiday = @holiday[1]
    today_is_company_holiday = today_holiday[:is_company_holiday]
    today_is_law_holiday = today_holiday[:is_law_holiday]
    tmr_is_company_holiday = tmr_holiday[:is_company_holiday]
    tmr_is_law_holiday = tmr_holiday[:is_law_holiday]
    return result unless today_is_company_holiday || today_is_law_holiday || tmr_is_law_holiday
    law_holiday_chunks, company_holiday_chunks = [], []
    if today_is_law_holiday
      law_holiday_chunks += today_tc_chunks 
      @law_work_day = true
      if tmr_tc_chunks.present?
        @tmr_normal_work_day = true unless tmr_is_company_holiday || tmr_is_law_holiday
        if tmr_is_company_holiday
          company_holiday_chunks = tmr_tc_chunks
          @tmr_com_work_day = true
        end
      end
    elsif today_is_company_holiday
      company_holiday_chunks += today_tc_chunks
      @com_work_day = true
      company_holiday_chunks += tmr_tc_chunks if !tmr_is_law_holiday
    end
    if tmr_is_law_holiday && tmr_tc_chunks.present?
      law_holiday_chunks += tmr_tc_chunks
      @tmr_law_work_day = true
    end
    [company_holiday_chunks, law_holiday_chunks]
  end

  def split_time_card
    result = {
      total_time: 0.0,
      work_time: 0.0,
      outgoing_time: 0.0,
      tc_chunks: [],
    }
    return result if @time_cards.blank?
    outgoing_time = 0
    outgoings_breaks = []
    normal_breaks = []
    all_chunks = []
    tc_array = []
    @time_cards.each_with_index do |time_card, idx|
      time_out = time_card.time_out
      next if time_out.blank?
      time_attend = time_card.time_attend
      tc_array << [time_attend, time_out]
      normals, outgoings = CommonCsv.time_card_breaks(time_card)
      outgoings_breaks += outgoings
      normal_breaks += normals
      all_breaks = @add_outgoing ? normals : normals + outgoings
      all_chunks += CustomDate.split_array([time_attend, time_out], all_breaks)
      result[:tc_end] = time_out if idx + 1 == @time_cards.size
      next unless idx.zero?
      @ignore_late_times &= time_card.late_removal?
      @ignore_late_time &= time_card.late_removal?
      result[:tc_start] = time_card.time_attend
    end
    all_chunks = CustomDate.merge_overlapped_inside_array(all_chunks.sort_by { |a| a[0] })
    all_breaks = @add_outgoing ? normal_breaks : normal_breaks + outgoings_breaks
    all_breaks = CustomDate.merge_overlapped_inside_array(all_breaks.sort_by { |a| a[0] })
    breaks = CustomDate.array_of_not_overlapped(all_breaks, all_chunks)
    plan_breaks = @plan_info[:break_chunks]
    all_breaks = CustomDate.merge_overlapped_inside_array((breaks + plan_breaks).sort_by { |a| a[0] })
    tc_array = CustomDate.merge_overlapped_inside_array(tc_array.sort_by { |a| a[0] })
    tc_chunks = CustomDate.array_of_not_overlapped(tc_array, all_breaks)
    
    outgoings_breaks = CustomDate.merge_overlapped_inside_array(outgoings_breaks.sort_by { |a| a[0] })
    outgoings_breaks.each do |og|
      outgoing_time += CustomDate.calc_time_chunks([og])
      plan_breaks.each do |plan_br|
        outgoing_time -= CustomDate.calc_time_by_array(og, plan_br)
      end
    end

    result[:tc_chunks] = tc_chunks
    result[:work_time] = CustomDate.calc_time_chunks(tc_chunks)
    result[:outgoing_time] = outgoing_time
    result[:total_time] = CustomDate.calc_time_chunks(tc_array)
    result
  end

  def pre_ot_request_approved_calc(date)
    hours = @pre_overtimes.select { |pr| pr.date == date }.inject(0.0) { |sum, pre_over| sum + pre_over.request_hours}
  end

  def calc_late_early
    result = {
      late_time: 0,
      late_times: 0,
      early_time: 0,
      early_times: 0,
      late_early_time: 0,
    }
    plan_chunks = @plan_info[:late_early_chunks]
    tc_chunks = @time_card_info[:tc_chunks]
    return result if plan_chunks.blank? || tc_chunks.blank? || (@is_flex_flexible && @plan_info[:has_day_off])
    plan_start, plan_end = plan_chunks.first[0], plan_chunks.last[1]
    tc_start, tc_end = @time_card_info[:tc_start], @time_card_info[:tc_end]
    plan_time = @plan_info[:plan_time]
    result[:late_time] = [CustomDate.calc_overlapped_time_by_arrays(plan_chunks, [[plan_start, tc_start]]) / 1.hour, plan_time].min unless @ignore_late_time
    result[:late_times] += 1 unless result[:late_time].zero? || @ignore_late_times
    result[:early_time] = [CustomDate.calc_overlapped_time_by_arrays(plan_chunks, [[tc_end, plan_end]]) / 1.hour, plan_time].min
    result[:early_times] += 1 unless result[:early_time].zero?
    result[:late_time] = result[:early_time] = 0 if @is_flex_flexible
    result[:late_early_time] = result[:late_time] + result[:early_time]
    result
  end

  def master_break_by_timeline work_time
    ab_time, ab_amount = 0, 0
    master_breaks = []
    MasterBreak::MAX.times do |idx|
      timeline_tmp = @master_break.send("timeline#{idx + 1}").to_i
      time_amount_tmp = @master_break.send("time_amount#{idx + 1}").to_i
      next unless timeline_tmp > 0

      # convert to HH:MM
      timeline_hour = CustomDate.convertTimeStamp(timeline_tmp)
      time_amount_hour = CustomDate.convertTimeStamp(time_amount_tmp)

      # convert Master Break to Float
      timeline = CustomDate.time_to_float(timeline_hour) / 1.hour
      time_amount = CustomDate.time_to_float(time_amount_hour) / 1.hour
      master_breaks << [timeline, time_amount]
    end
    master_breaks.each do |mb|
      ab_time, ab_amount = mb if work_time >= mb[0]
    end
    [ab_time.hour, ab_amount.hour]
  end

  def night_hour_plan_chunks plan_chunks
    today_begin, today_end, tmr_begin, tmr_end = @date_info
    result_pkg = []
    @night_hours.each do |pkg_chunk|
      next if pkg_chunk.blank?
      plan_chunks.each do |plan_chunk|
        overlapped = CustomDate.overlapped_points_by_array(plan_chunk, pkg_chunk)
        result_pkg << overlapped if overlapped.present?
      end
    end
    result_pkg
  end
end