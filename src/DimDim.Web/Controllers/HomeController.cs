using System.Diagnostics;
using DimDim.Web.Data;
using Microsoft.AspNetCore.Mvc;
using DimDim.Web.Models;
using Microsoft.EntityFrameworkCore;

namespace DimDim.Web.Controllers;

public class HomeController(DimDimContext context) : Controller
{
    public async Task<IActionResult> Index()
    {
        var contas = await context.Contas.Include(c => c.Transacoes).ToListAsync();
        ViewBag.TotalContas = contas.Count;
        ViewBag.TotalTransacoes = contas.Sum(c => c.Transacoes.Count);
        ViewBag.SaldoTotal = contas.Sum(c => c.Saldo);
        ViewBag.Ultimas = await context.Transacoes.Include(t => t.Conta)
            .OrderByDescending(t => t.Data).ThenByDescending(t => t.Id).Take(5).ToListAsync();
        return View();
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}
