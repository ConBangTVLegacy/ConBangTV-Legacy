//! Bước 2: kiểm thư viện chuẩn Rust + tokio + reqwest/rustls trên iOS 6 (armv7, target tự định nghĩa tools/rust/armv7-apple-ios6.json).
//! App ObjC gọi qua C: cbr_selftest() / cbr_fetch(url) trả chuỗi UTF-8 (giải phóng bằng cbr_free).

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();

fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("không tạo được tokio runtime")
    })
}

fn client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .user_agent("ConBangLegacy-spike/0.1 (iOS 6; Rust)")
            .timeout(Duration::from_secs(20))
            .build()
            .expect("không tạo được reqwest client")
    })
}

fn out(s: String) -> *mut c_char {
    CString::new(s.replace('\0', " ")).unwrap_or_default().into_raw()
}

/// Thử các phần của std hay đụng tới API hệ điều hành: đồng hồ, thời gian thực, số ngẫu nhiên (HashMap), luồng, khoá.
#[no_mangle]
pub extern "C" fn cbr_selftest() -> *mut c_char {
    let start = Instant::now();
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let mut map = HashMap::new();
    for i in 0..1000u32 {
        map.insert(i, i * 2);
    }
    let lock = Mutex::new(0u64);
    let sum = std::thread::scope(|s| {
        for t in 0..4u64 {
            let lock = &lock;
            s.spawn(move || {
                for i in 0..10_000u64 {
                    *lock.lock().unwrap() += i * t;
                }
            });
        }
        *lock.lock().unwrap()
    });
    std::thread::sleep(Duration::from_millis(20));
    let rt_ok = runtime().block_on(async {
        tokio::time::sleep(Duration::from_millis(10)).await;
        true
    });
    out(format!(
        "std OK: unix={now}, HashMap={} mục, 4 luồng tổng={sum}, ngủ 20 ms → đo {} ms, tokio={rt_ok}",
        map.len(),
        start.elapsed().as_millis()
    ))
}

/// Tải một địa chỉ bằng reqwest (rustls, gốc Mozilla đóng kèm); trả về mã HTTP, phiên bản HTTP, số byte, thời gian.
#[no_mangle]
pub extern "C" fn cbr_fetch(url: *const c_char) -> *mut c_char {
    if url.is_null() {
        return out("LỖI: url rỗng".into());
    }
    let url = unsafe { CStr::from_ptr(url) }.to_string_lossy().into_owned();
    let start = Instant::now();
    let result = runtime().block_on(async {
        let resp = client().get(&url).send().await?;
        let head_ms = start.elapsed().as_millis();
        let status = resp.status().as_u16();
        let version = format!("{:?}", resp.version());
        let body = resp.bytes().await?;
        Ok::<_, reqwest::Error>((status, version, body.len(), head_ms))
    });
    let secs = start.elapsed().as_secs_f64();
    out(match result {
        Ok((status, version, len, head_ms)) => format!(
            "OK — HTTP {status} {version}, {:.2} MB trong {secs:.2} s (phần đầu sau {head_ms} ms) = {:.2} MB/s",
            len as f64 / 1048576.0,
            len as f64 / 1048576.0 / secs
        ),
        Err(e) => format!("LỖI {e:?} ({secs:.2} s)"),
    })
}

#[no_mangle]
pub extern "C" fn cbr_free(p: *mut c_char) {
    if !p.is_null() {
        unsafe { drop(CString::from_raw(p)) };
    }
}
