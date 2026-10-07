using DimDim.Web.Data;
using DimDim.Web.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace DimDim.Web.Controllers;

public class ContasController(DimDimContext context) : Controller
{
    public async Task<IActionResult> Index() =>
        View(await context.Contas.Include(c => c.Transacoes).OrderBy(c => c.Nome).ToListAsync());

    public async Task<IActionResult> Details(int? id)
    {
        if (id is null) return NotFound();
        var conta = await context.Contas.Include(c => c.Transacoes).FirstOrDefaultAsync(c => c.Id == id);
        return conta is null ? NotFound() : View(conta);
    }

    public IActionResult Create() => View(new Conta());

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create([Bind("Nome,Instituicao,Tipo,SaldoInicial")] Conta conta)
    {
        if (!ModelState.IsValid) return View(conta);
        context.Add(conta);
        await context.SaveChangesAsync();
        TempData["Success"] = "Conta criada com sucesso.";
        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> Edit(int? id)
    {
        if (id is null) return NotFound();
        var conta = await context.Contas.FindAsync(id);
        return conta is null ? NotFound() : View(conta);
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(int id, [Bind("Id,Nome,Instituicao,Tipo,SaldoInicial")] Conta conta)
    {
        if (id != conta.Id) return NotFound();
        if (!ModelState.IsValid) return View(conta);
        try
        {
            context.Update(conta);
            await context.SaveChangesAsync();
            TempData["Success"] = "Conta atualizada com sucesso.";
        }
        catch (DbUpdateConcurrencyException)
        {
            if (!await context.Contas.AnyAsync(c => c.Id == id)) return NotFound();
            throw;
        }
        return RedirectToAction(nameof(Index));
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(int id)
    {
        var conta = await context.Contas.Include(c => c.Transacoes).FirstOrDefaultAsync(c => c.Id == id);
        if (conta is null) return NotFound();
        if (conta.Transacoes.Count != 0)
        {
            TempData["Error"] = "A conta não pode ser excluída porque possui transações.";
            return RedirectToAction(nameof(Index));
        }
        context.Remove(conta);
        await context.SaveChangesAsync();
        TempData["Success"] = "Conta excluída com sucesso.";
        return RedirectToAction(nameof(Index));
    }
}
