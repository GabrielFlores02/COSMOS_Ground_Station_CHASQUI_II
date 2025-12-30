# ============================================================================
# SCRIPT 11: IMPORTADOR DE CALENDARIO GMAT
# ============================================================================
# Archivo: procedures/operations/gmat_calendar_import.rb

load_utility 'ground_station_library'
require 'json'

def import_gmat_schedule(json_file = nil)
  puts "="*70
  puts "IMPORTADOR DE CALENDARIO GMAT"
  puts "="*70
  
  # Ubicación por defecto del archivo generado por GMAT
  default_json = File.join(Cosmos::USERPATH, 'outputs', 'planning', 'pass_schedule.json')
  schedule_file = json_file || default_json
  
  unless File.exist?(schedule_file)
    puts "\n✗ ERROR: Archivo no encontrado: #{schedule_file}"
    puts "\nPrimero debe ejecutar la predicción GMAT:"
    puts "  cd tools/gmat"
    puts "  ./run_gmat_prediction.sh"
    return false
  end
  
  # Cargar JSON
  begin
    schedule_data = JSON.parse(File.read(schedule_file), symbolize_names: true)
    puts "\n✓ Calendario cargado: #{schedule_data.length} pases"
  rescue => e
    puts "\n✗ Error parseando JSON: #{e.message}"
    return false
  end
  
  # Validar y filtrar pases
  valid_passes = []
  now = Time.now
  
  schedule_data.each do |pass_entry|
    begin
      aos = Time.parse(pass_entry[:aos])
      los = Time.parse(pass_entry[:los])
      
      # Solo pases futuros
      next if los < now
      
      # Validar datos mínimos
      next unless pass_entry[:duration_minutes]
      next unless pass_entry[:max_elevation]
      
      valid_passes << pass_entry
    rescue => e
      puts "  ⚠ Pase inválido: #{e.message}"
    end
  end
  
  puts "  Pases válidos (futuros): #{valid_passes.length}"
  
  if valid_passes.empty?
    puts "\n⚠ No hay pases futuros en el calendario"
    puts "Regenerar predicción GMAT con época más reciente"
    return false
  end
  
  # Importar al programador de COSMOS
  puts "\n[IMPORT] Importando al programador de COSMOS..."
  
  require_relative 'pass_scheduler'
  scheduler = PassScheduler.new
  
  imported_count = 0
  skipped_count = 0
  
  valid_passes.each do |pass_entry|
    aos_time = Time.parse(pass_entry[:aos])
    duration = pass_entry[:duration_minutes].to_i
    max_el = pass_entry[:max_elevation].to_f
    
    # Determinar si auto-comandos según prioridad
    auto_commands = (pass_entry[:priority] == 'high')
    
    # Importar al scheduler
    begin
      pass_id = scheduler.add_pass(
        aos_time,
        duration,
        max_el,
        auto_commands: auto_commands,
        auto_download: true
      )
      imported_count += 1
    rescue => e
      puts "  ⚠ No se pudo importar pase: #{e.message}"
      skipped_count += 1
    end
  end
  
  puts "\n✓ Importación completada:"
  puts "  Importados: #{imported_count}"
  puts "  Omitidos: #{skipped_count}"
  
  # Mostrar resumen
  display_imported_schedule(scheduler)
  
  return true
end

def display_imported_schedule(scheduler)
  puts "\n" + "="*70
  puts "CALENDARIO IMPORTADO"
  puts "="*70
  
  scheduler.list_passes()
  
  # Estadísticas
  next_pass = scheduler.get_next_pass()
  
  if next_pass
    aos_time = Time.at(next_pass[:aos])
    time_to_aos = ((aos_time - Time.now) / 3600.0).round(1)
    
    puts "\n📡 PRÓXIMO PASE:"
    puts "  Inicio: #{aos_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  En: #{time_to_aos} horas"
    puts "  Duración: #{next_pass[:duration]} min"
    puts "  Max El: #{next_pass[:max_elevation]}°"
  end
  
  puts "="*70
end

# Función de conveniencia para actualizar calendario
def update_gmat_schedule
  puts "\n🔄 ACTUALIZANDO CALENDARIO DESDE GMAT..."
  puts "="*70
  
  # Verificar que exista el script
  gmat_script = File.join(Cosmos::USERPATH, '..', 'tools', 'gmat', 'run_gmat_prediction.sh')
  
  if File.exist?(gmat_script)
    puts "\nEjecutando predicción GMAT..."
    puts "(Esto puede tomar 2-3 minutos)\n"
    
    # Ejecutar script GMAT
    system("bash #{gmat_script}")
    
    if $?.success?
      puts "\n✓ Predicción GMAT completada"
      
      # Importar resultados
      wait(2)
      import_gmat_schedule()
    else
      puts "\n✗ Error ejecutando GMAT"
      return false
    end
  else
    puts "\n⚠ Script GMAT no encontrado: #{gmat_script}"
    puts "Importar manualmente el calendario"
    return false
  end
  
  return true
end

# Ejecución desde Script Runner
if __FILE__ == $0
  puts "OPCIONES:"
  puts "1. Importar calendario existente"
  puts "2. Actualizar desde GMAT y luego importar"
  
  option = ask("Seleccione opción (1/2):").to_i
  
  case option
  when 1
    import_gmat_schedule()
  when 2
    update_gmat_schedule()
  else
    puts "Opción inválida"
  end
end
