use actix_files::Files;
use actix_web::{web, App, HttpResponse, HttpServer};

async fn index() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(include_str!("../static/index.html"))
}

async fn template_devcontainer_json() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("application/json")
        .insert_header(("Content-Disposition", "attachment; filename=\"devcontainer.json\""))
        .body(include_str!("../.devcontainer/devcontainer.json"))
}

async fn template_dockerfile() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/plain")
        .insert_header(("Content-Disposition", "attachment; filename=\"Dockerfile\""))
        .body(include_str!("../.devcontainer/Dockerfile"))
}

async fn template_managed_settings() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("application/json")
        .insert_header(("Content-Disposition", "attachment; filename=\"managed-settings.json\""))
        .body(include_str!("../.devcontainer/managed-settings.json"))
}

async fn template_firewall() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/plain")
        .insert_header(("Content-Disposition", "attachment; filename=\"init-firewall.sh\""))
        .body(include_str!("../.devcontainer/init-firewall.sh"))
}

async fn template_refresh_dns() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/plain")
        .insert_header(("Content-Disposition", "attachment; filename=\"refresh-firewall-dns.sh\""))
        .body(include_str!("../.devcontainer/refresh-firewall-dns.sh"))
}

async fn template_firewall_domains() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/plain")
        .insert_header(("Content-Disposition", "attachment; filename=\"firewall-allowed-domains.conf\""))
        .body(include_str!("../.devcontainer/firewall-allowed-domains.conf"))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    println!("Serving presentation at http://localhost:{port}");
    println!("Template files available at:");
    println!("  /template/devcontainer.json");
    println!("  /template/Dockerfile");
    println!("  /template/managed-settings.json");
    println!("  /template/init-firewall.sh");
    println!("  /template/refresh-firewall-dns.sh");
    println!("  /template/firewall-allowed-domains.conf");

    HttpServer::new(|| {
        App::new()
            .route("/", web::get().to(index))
            .route("/template/devcontainer.json", web::get().to(template_devcontainer_json))
            .route("/template/Dockerfile", web::get().to(template_dockerfile))
            .route("/template/managed-settings.json", web::get().to(template_managed_settings))
            .route("/template/init-firewall.sh", web::get().to(template_firewall))
            .route("/template/refresh-firewall-dns.sh", web::get().to(template_refresh_dns))
            .route("/template/firewall-allowed-domains.conf", web::get().to(template_firewall_domains))
            .service(Files::new("/static", "static").show_files_listing())
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
